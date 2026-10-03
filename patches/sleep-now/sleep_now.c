/* sleep-now: the Sleep item puts the iPod to sleep at once.
 *
 * In the stock firmware, the Sleep item (0x1d83fc) turns the backlight off and starts the
 * idle timer (500 ms). The idle timer handler (0x1d8a40) sleeps only when its gate passes
 * (0x1d938c → 0x1d8444 → 0x1d8670, 0x1d8718). The gate refuses the sleep while a keep-awake
 * slot is active, while the firmware thinks that power is connected, and in other states.
 * Then the wheel does not respond and the screen stays on until the gate passes.
 *
 * App command 7 (0x1e8cd4) calls the Sleep item handler at 0x1e8ce8. A table entry at
 * 0x69fd2c also points to it. Both hooks call the stock handler. Then they call the stock
 * sleep part of 0x1d8cd0 (0x1d9308) at once. That part saves the settings, writes the cache
 * (0x1ee8d0, 0x1ed828), and calls the sleep function 0xb43dc. 0xb43dc turns the display off, tells the storage to
 * sleep (keep-awake message type 4) and cuts the storage power.
 *
 * 0x1ee8d0 does not sleep if 0x1ecc8c says that external power is connected. It keeps the
 * display on (Apple's behaviour on power). The firmware reads a saved copy of the power pins,
 * and this copy can be wrong after a computer session. During a forced sleep, hook_power_test
 * reads the pins: GPIOL bit 0x08 (FireWire or charger, low = power) and bit 0x10 (USB, high =
 * power, and 0x265698 must not return 1, as in 0x9e664). On real power, the stock behaviour
 * stays.
 *
 * If a voice memo records (byte +0x66 of component 0x3d00), the hooks do not force a sleep.
 * See re/sleep.md.
 */

int fw_sleep_item(void *ctl, int a, int b, int c);     /* 0x1d83fc: the Sleep item */
int fw_go_sleep(void *ctl);                            /* 0x1d9308: the sleep part of 0x1d8cd0 */
int fw_power_test(void *app);                          /* 0x1ecc8c: external power (saved pins) */
int fw_power_source(void);                             /* 0x265698: reads the power pins */
void fw_timer_stop(void *timer);                       /* 0x151c98 */
unsigned char *fw_recorder(void);                      /* 0x1c1f5c: component 0x3d00 */

#define GPIOL_INPUT_VAL (*(volatile unsigned *)0x6000d13c)
#define PIN_FIREWIRE 0x08
#define PIN_USB 0x10
#define IDLE_TIMER 0x48
#define SLEEP_TIMER 0x74
#define RECORDING 0x66

static int forcing;

static void force_sleep(char *ctl)
{
    unsigned char *rec = fw_recorder();
    if (rec && rec[RECORDING])
        return;
    fw_timer_stop(ctl + IDLE_TIMER);
    fw_timer_stop(ctl + SLEEP_TIMER);
    forcing = 1;
    fw_go_sleep(ctl);
    forcing = 0;
}

int hook_sleep_item(void *ctl, int a, int b, int c)
{
    int r = fw_sleep_item(ctl, a, b, c);
    force_sleep(ctl);
    return r;
}

int hook_power_test(void *app)
{
    unsigned pins;
    if (!forcing)
        return fw_power_test(app);
    pins = GPIOL_INPUT_VAL;
    if ((pins & PIN_FIREWIRE) == 0)
        return 1;
    return (pins & PIN_USB) != 0 && fw_power_source() != 1;
}
