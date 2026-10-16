/* instant-save: the iPod saves its settings at each change in Settings > Main Menu
 * (RetailOS 1.3, iPod Video).
 *
 * The firmware does not write the settings when the owner changes a row. The setter 0x19351c only
 * changes the main menu mask and sets the byte "changed" (settings data + 0xb74). The settings file
 * is written only at a sleep (0x1ee8d0) or at a save of all data (0xbc094, for example at a disk
 * change). A restart with Menu+Select runs no save, thus a change since the last sleep is lost.
 * The research is in re/album-artist.md, section "The save of the settings".
 *
 * Hook: the first instruction of the setter 0x19351c. The firmware rows of Settings > Main Menu
 * (0x192794) and the Album Artists row of the album-artists patch both call it. After the change,
 * the patch calls 0xbbf1c. That function writes the settings only if the byte "changed" is set,
 * thus a selection that changes nothing writes nothing. */

void set_continue(void);                                                           /* 0x193520 */
void write_settings(void *settings_data);                                          /* 0xbbf1c */

#define FIELD(type, object, offset) (*(type *)((char *)(object) + (offset)))

/* The replaced first instruction of 0x19351c, then the rest of the function. */
__attribute__((naked)) void set_original(void *settings, int label, int on)
{
    __asm__ volatile("push {r4, r5, r6, r7, r8, lr}\n\tb set_continue\n");
}

/* settings + 0x98 is the main browser. The settings data are at main browser + 0xca0, as in
 * 0x19351c and 0xbc094. */
void hook_set(void *settings, int label, int on)
{
    set_original(settings, label, on);
    write_settings(FIELD(void *, FIELD(void *, settings, 0x98), 0xca0));
}
