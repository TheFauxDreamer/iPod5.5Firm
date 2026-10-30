/* flash-wake-on-input: start the flash storage when you touch a control after a long pause.
 * Use it with flash-keep-awake if the first song after a long pause starts late. Each patch
 * also operates alone.
 *
 * The hook replaces "bl 0x1d813c" at 0x1d8344, in the event handler 0x1d81cc of the UI task.
 * 0x1d813c starts the idle timer again and switches the display on. It runs for a button
 * event. It does not run for a turn of the wheel (codes 0x10 and 0x1c). If no keep-awake slot
 * is active, the storage is off, and the hook asks for the storage in slot WAKE_SLOT, as the
 * firmware's own clients do (always on, then a time).
 *
 * The hook does not examine each event. After a wake, slot WAKE_SLOT keeps the storage on for
 * wake_ms, thus the hook does the next check after wake_ms. If a slot is active, the hook does
 * the next check after CHECK_GAP_US. The time comes from USEC_TIMER (0x60005010), the counter
 * of the firmware's busy wait (0x282870). The unsigned subtraction is correct when the counter
 * wraps (each 71.6 minutes).
 *
 * flash-keep-awake also uses slot WAKE_SLOT (after a sleep). See re/play-latency.md.
 */

#define WAKE_SLOT 40                       /* no firmware code uses this slot as a constant */
#define CHECK_GAP_US 1000000u              /* no check for this time after a check that found a slot */
#define USEC_TIMER (*(volatile unsigned *)0x60005010)

void ka_always_on(int slot, int arg);      /* keep-awake message type 0 */
void ka_timed(int slot, int ms);           /* keep-awake message type 2 */
void fw_user_event(void *ui, int on);      /* the original call at 0x1d8344 */
int fw_any_slot(void);                     /* 1: a slot is active (0x94cec) */

unsigned wake_ms = 1800000;    /* the option "time": 30 minutes is the default */
static unsigned last_check;    /* USEC_TIMER at the last check */
static unsigned check_gap;     /* 0 at the start: the first event does a check */

__attribute__((minsize)) void hook_user_event(void *ui, int on)
{
    unsigned now;
    fw_user_event(ui, on);
    now = USEC_TIMER;
    if (now - last_check < check_gap)
        return;
    last_check = now;
    if (fw_any_slot()) {
        check_gap = CHECK_GAP_US;
        return;
    }
    ka_always_on(WAKE_SLOT, 0);
    ka_timed(WAKE_SLOT, wake_ms);
    check_gap = wake_ms * 1000u;   /* the maximum, 3600 s, fits in 32 bits */
}
