/* flash-keep-awake: a longer keep-awake time for the storage, and a storage wake when the
 * iPod wakes from sleep.
 *
 * The task at osos 0x284b0c keeps the storage awake for its clients. A client sends a message
 * with a time in milliseconds (message type 2, time at +0x18). The clients send 501 or 1001.
 * When all times are over, the task tells the storage task to sleep: the storage gets STANDBY
 * IMMEDIATE and then its power is switched off (GPO32 bit 30). A flash adapter must then start
 * its cards again at the next access, and the next song starts 3-6 s late.
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
 * All the power paths of the firmware stay the same. See re/play-latency.md.
 */

#define MIN_MS 1800000
#define WAKE_SLOT 40            /* no firmware code uses this slot as a constant */
#define SLOTS 45
#define ALWAYS_ON (-1)

int fw_resume_tail(int a, int b);           /* the original call at 0xb45f4 */
void ka_always_on(int slot, int arg);       /* keep-awake message type 0 */
void ka_timed(int slot, int ms);            /* keep-awake message type 2 */
extern volatile unsigned char ka_active[SLOTS];     /* the slot flags of the task */
extern volatile int ka_time[SLOTS];                 /* the time left of each slot */

__attribute__((naked)) void hook_keep_awake_time(void)
{
    __asm__ volatile(
        "ldr   r1, [r4, #0x18]\n"
        "cmp   r1, #1\n"
        "bxls  lr\n"
        "cmn   r1, #1\n"
        "bxeq  lr\n"
        "ldr   ip, 1f\n"
        "cmp   r1, ip\n"
        "movlo r1, ip\n"
        "bx    lr\n"
        "1: .word %c0\n"
        :: "i"(MIN_MS));
}

int hook_after_wake(int a, int b)
{
    int r = fw_resume_tail(a, b);
    ka_always_on(WAKE_SLOT, 0);
    ka_timed(WAKE_SLOT, MIN_MS);
    return r;
}

int hook_storage_in_use(void)
{
    int i;
    for (i = 0; i < SLOTS; i++)
        if (ka_active[i] && ka_time[i] == ALWAYS_ON)
            return 1;
    return 0;
}
