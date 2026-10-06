/* flash-keep-awake: "SSD mode" for flash storage. A longer keep-awake time for the storage, a
 * storage wake when the iPod wakes from sleep or when you touch a control, and a settle time
 * before the storage power goes off. The patch does nothing on a hard drive.
 *
 * The task at osos 0x284b0c keeps the storage awake for its clients. A client sends a message
 * with a time in milliseconds (message type 2, time at +0x18). The clients send 501 or 1001.
 * When all times are over, the task tells the storage task to sleep: the storage gets STANDBY
 * IMMEDIATE and then its power is switched off (GPO32 bit 30). A flash adapter must then start
 * its cards again at the next access, and the next song starts 3-6 s late.
 *
 * Hook 6 replaces the last call of the byte swap (0x1430a8) at 0x142f94, at the end of the
 * IDENTIFY function 0x142e48. The firmware runs this function one time at start. The hook does
 * the swap, then reads the IDENTIFY data and sets ka_flash. The data starts 0x14 bytes before
 * the swapped serial number. Flash is: a model that starts with "iFlash" (rockpod issue #37:
 * "iFlash-Platform iPod Adapters"), or no rotation (word 217 = 1), or CompactFlash (word 0 =
 * 0x848A). The iFlash adapter sets none of these words, thus the model text is necessary. The
 * area for the patch is small, thus the patch does not examine the TRIM and CFA feature bits.
 * Hooks 1, 2, 4 and 5 keep the firmware behaviour if ka_flash is 0. Hook 3 is the same for all
 * storage types.
 *
 * Hook 1 replaces "ldr r1, [r4, #0x18]" at 0x284c7c. It reads the same time and makes a time
 * that is shorter than MIN_MS equal to MIN_MS. It does not change 0, 1 or 0xffffffff. The
 * helper 0x94d80 adds 1 to the time, thus a client that releases its slot ("0 ms") sends 1.
 * The caller uses r0, r1, r2 and r4 after the hook. The hook changes only r1 and ip.
 *
 * Hook 2 replaces the last call of the sleep function (0xb43dc), at 0xb45f4, which runs after
 * the iPod wakes. Before the iPod sleeps, the firmware puts the storage to sleep and cuts its
 * power. The hook asks for the storage in slot WAKE_SLOT, as the firmware's own clients do
 * (always on, then a time). The storage then starts while you look for a song.
 *
 * Hook 3 replaces "bl 0x94cec" at 0x1d871c, in the sleep gate. 0x94cec returns 1 if a slot is
 * active, and then the gate refuses the sleep. This gate also completes a Sleep that the
 * firmware deferred. With hook 1, each access keeps a slot active for MIN_MS, thus the iPod
 * did not sleep. The hook returns 1 only for a slot that is always on (time 0xffffffff): a
 * client that uses the storage now. A timed slot does not stop the sleep. The sleep function
 * then puts the storage to sleep as usual (message type 4, 0x94e08).
 *
 * Hook 4 replaces "bl 0x1d813c" at 0x1d8344, in the event handler 0x1d81cc of the UI task.
 * 0x1d813c starts the idle timer again and switches the display on. It runs for a button or
 * a wheel event. If no slot is active, the storage is off, and the hook wakes it as hook 2 does.
 *
 * Hook 5 replaces the power-off call "bl 0x265cc8" at 0x23344c, in the storage "set power"
 * method 0x233358. The firmware sends STANDBY IMMEDIATE, waits for the drive and switches the
 * controller off before this call. The hook waits SETTLE_MS before the power cut. The iFlash
 * has no power management, and it can lose a write if the power goes off too early. rockpod
 * waits 500 ms for the same reason (rockpod issue #37).
 *
 * All the power paths of the firmware stay the same. See re/play-latency.md.
 */

#define MIN_MS 1800000
#define SETTLE_MS 500
#define WAKE_SLOT 40            /* no firmware code uses this slot as a constant */
#define SLOTS 45
#define ALWAYS_ON (-1)

int fw_resume_tail(int a, int b);           /* the original call at 0xb45f4 */
void ka_always_on(int slot, int arg);       /* keep-awake message type 0 */
void ka_timed(int slot, int ms);            /* keep-awake message type 2 */
extern volatile unsigned char ka_active[SLOTS];     /* the slot flags of the task */
extern volatile int ka_time[SLOTS];                 /* the time left of each slot */
void fw_swap(void *ata, unsigned char *p, unsigned n);  /* the byte swap at 0x142f94 */
void fw_user_event(void *ui, int on);       /* the original call at 0x1d8344 */
void fw_drive_power(int on);                /* the original call at 0x23344c */
void fw_task_sleep(int ms);
int fw_any_slot(void);                     /* 1: a slot is active (0x94cec) */

unsigned char ka_flash;     /* 1: the storage is flash. Hook 1 reads it by name. */

__attribute__((naked)) void hook_keep_awake_time(void)
{
    __asm__ volatile(
        "ldr   r1, [r4, #0x18]\n"
        "cmp   r1, #1\n"
        "bxls  lr\n"
        "cmn   r1, #1\n"
        "bxeq  lr\n"
        "ldr   ip, 2f\n"
        "ldrb  ip, [ip]\n"
        "cmp   ip, #0\n"
        "bxeq  lr\n"
        "ldr   ip, 1f\n"
        "cmp   r1, ip\n"
        "movlo r1, ip\n"
        "bx    lr\n"
        "1: .word %c0\n"
        "2: .word ka_flash\n"
        :: "i"(MIN_MS));
}

/* Ask for the storage in slot WAKE_SLOT, as the firmware's own clients do (always on, then a time). */
__attribute__((minsize)) static void wake_storage(int needed)
{
    if (ka_flash && needed) {
        ka_always_on(WAKE_SLOT, 0);
        ka_timed(WAKE_SLOT, MIN_MS);
    }
}

__attribute__((minsize)) int hook_after_wake(int a, int b)
{
    int r = fw_resume_tail(a, b);
    wake_storage(1);
    return r;
}

__attribute__((minsize)) int hook_storage_in_use(void)
{
    int i;
    for (i = 0; i < SLOTS; i++)
        if (ka_active[i] && ka_time[i] == ALWAYS_ON)
            return 1;
    return 0;
}

__attribute__((minsize)) void hook_user_event(void *ui, int on)
{
    fw_user_event(ui, on);
    wake_storage(!fw_any_slot());
}

/* The firmware always calls 0x265cc8 with 0 (off) at 0x23344c. */
__attribute__((minsize)) void hook_drive_power_off(void)
{
    if (ka_flash)
        fw_task_sleep(SETTLE_MS);
    fw_drive_power(0);
}

/* "iFlash" at the start of the model, as 16-bit words in the swapped (text) byte order */
#define TEXT2(a, b) ((a) | (b) << 8)

__attribute__((minsize)) void hook_identify(void *ata, unsigned char *serial, unsigned n)
{
    const unsigned short *w = (const unsigned short *)(serial - 0x14);

    fw_swap(ata, serial, n);
    ka_flash = (w[27] == TEXT2('i', 'F') && w[28] == TEXT2('l', 'a') && w[29] == TEXT2('s', 'h'))
               || w[217] == 1 || w[0] == 0x848a;
}
