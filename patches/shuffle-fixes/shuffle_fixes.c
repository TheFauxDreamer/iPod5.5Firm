/* shuffle-fixes: corrections of the music shuffle (RetailOS 1.3, iPod Video).
 *
 * The research is in re/shuffle.md, section "Known bugs in the firmware". The "bytes" of patch.json
 * correct Bug 1 (an index equal to n) and Bug 4 (more than 32767 songs). This file corrects the
 * other two bugs.
 *
 * Bug 2: the seeds 0, 0x7fffffff and 0x80000001 stop the Park-Miller generator at 0x7fffffff.
 * Hook: the call of the seed function at 0xe59a0 in the random index 0xe5978. The firmware reads
 * the seed only there, one time after each start. The card game 0x12d494 has its own call of
 * 0x55c. The patch does not change it.
 *
 * Bug 3: the shuffle of the songs in each album (settings byte +0x93) swaps work[k] with work[j],
 * but j is from 0, not from the start of the album. Hook: the call of the random index at 0x946d8.
 * At this call r8 is the start of the album. 0xe5978 and 0xaf4b4 keep r8. */

unsigned seed_source(void);                                                        /* 0x55c */
int random_index(int n);                                                           /* 0xe5978 */

/* A bad seed becomes 1, 0x7ffffffe or 0x80000000. These seeds do not stop the generator. */
unsigned hook_seed(void)
{
    unsigned s = seed_source();
    if (s == 0 || s == 0x7fffffff || s == 0x80000001)
        s ^= 1;
    return s;
}

/* The index in the album, plus the start of the album (r8 of the caller). */
__attribute__((naked)) int hook_album_index(int n)
{
    __asm__ volatile("push {r4, lr}\n\tbl random_index\n\tadd r0, r0, r8\n\tpop {r4, pc}\n");
}
