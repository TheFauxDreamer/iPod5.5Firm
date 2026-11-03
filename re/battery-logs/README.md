# Battery logs from the owner's iPod

These files are the raw logs of the patch `battery-log` from one iPod 5.5G with a larger battery. Each line has the seconds, the raw battery value, the icon value and the fourth column. The fourth column is not the charger state. Refer to [../battery.md](../battery.md).

| File | Test | Notes |
|---|---|---|
| `2026-10-31-battery-1.txt` | Music on battery, 2.77 hours | Not from a full charge. |
| `2026-11-01-battery-2-to-empty.txt` | Music on battery until the iPod stopped, 18.3 hours | After a charge of 1 hour. It is the only log to empty. |
| `2026-11-02-wall-charger.txt` | Music on a wall charger | The file had 18 zero bytes after the header. This copy does not have them. |
| `2026-11-03-after-charge.txt` | Music on battery after a charge overnight | The start of the next test. |

Do not change these files. Add a new file for each new log.
