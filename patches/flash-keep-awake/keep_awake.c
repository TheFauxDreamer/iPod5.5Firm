/* flash-keep-awake: a longer keep-awake time for the storage.
 *
 * The task at osos 0x284b0c keeps the storage awake for its clients. A client sends a message
 * with a time in milliseconds (message type 2, time at +0x18). The clients send 501 or 1001.
 * When all times are over, the task tells the storage task to sleep: the storage gets STANDBY
 * IMMEDIATE and then its power is switched off (GPO32 bit 30). A flash adapter must then start
 * its cards again at the next access, and the next song starts 3-6 s late.
 *
 * The hook replaces "ldr r1, [r4, #0x18]" at 0x284c7c. It reads the same time and makes a
 * time that is shorter than MIN_MS equal to MIN_MS. It does not change 0 (release now) or
 * 0xffffffff (no limit). All the power paths of the firmware stay the same.
 *
 * The caller uses r0, r1, r2 and r4 after the hook. The hook changes only r1 and ip.
 * See re/play-latency.md.
 */

#define MIN_MS 120000

__attribute__((naked)) void hook_keep_awake_time(void)
{
    __asm__ volatile(
        "ldr   r1, [r4, #0x18]\n"
        "cmp   r1, #0\n"
        "bxeq  lr\n"
        "cmn   r1, #1\n"
        "bxeq  lr\n"
        "ldr   ip, 1f\n"
        "cmp   r1, ip\n"
        "movlo r1, ip\n"
        "bx    lr\n"
        "1: .word %c0\n"
        :: "i"(MIN_MS));
}
