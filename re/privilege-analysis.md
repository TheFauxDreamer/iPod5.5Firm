# The analysis of the administrator rights

This note records why iPodFirm needs administrator rights, and why the app now has no root code. The measurements are from 2026-11-02, on one Mac and one real iPod. The iPod has the Mac format (Apple partition map), 1 TB and a block size of 2048 bytes.

## The reports

Issues #2, #3 and #4 on GitHub are from one user with the public release.

| Issue | Fault | Cause |
|---|---|---|
| #2 | The app cannot write `Staging/flash.bin`. | `Staging` has the owner root. |
| #3 | The app cannot move `Staging`. | The same cause. macOS refuses the move of a folder of root. |
| #4 | The firmware partition has no empty area for rsrc. | This is not a permission fault. `FirmwarePartition.makeRoom` found no empty area. The issue has no log file, so the cause is not known. |

Before commit `ce5c6d7`, the helper ran as root, made `Staging`, and gave only the file to the user. The location of the folder did not cause the fault.

The public release has an ad-hoc signature, so it cannot use the daemon. Thus all users of the release had the password path.

## The location of the data

`~/Library/Application Support/iPodFirm` is already in the folder of the user. The mode 700 and the ACL of `Application Support` in the report are normal.

A move of the data gives no gain, because the fault follows a process of root to any folder. `~/Documents` is worse, because macOS protects it and iCloud can sync it.

The permanent data stays in the folder. Only the temporary files move to `~/Library/Caches/iPodFirm/Staging`. Thus an old `Staging` folder of root has no effect, and the app needs no repair.

## What needs a privilege

Only the open of `/dev/rdiskN` needs a privilege. The list, the unmount, the eject, the backups, the parsers and the checks need none.

## The measurements

The test process had no Full Disk Access: it could not read `TCC.db`.

| Test | Result |
|---|---|
| The device node of the iPod | `crw-r----- root operator`. "Removable" does not change it. |
| `dd` read as the user | `Permission denied` |
| `authopen`, read-only, `/dev/rdisk15`, volume mounted | A descriptor. The read gives 2048 bytes with the signature `ER`. |
| `authopen`, read-write, `/dev/rdisk15`, volume mounted | No descriptor. `authopen` sends the bytes `00 10`. The value 0x10 is `EBUSY`. |
| `authopen`, read-write, `/dev/rdisk15s2`, volume mounted | A descriptor with the mode `O_RDWR`. |
| `authopen`, read-write, `/dev/rdisk15`, volume not mounted | A descriptor. Thus the `EBUSY` above came from the mounted volume. |
| One `AuthorizationRef`, read and write rights, 5 opens | One password prompt. The opens took 0.1 second each. |

The right `sys.openfile.` has `authenticate-user: true`, `group: admin`, `timeout: 300` and `shared: false`.

These tests did not do a write. The disk image test does a real flash with no root code.

A later test with the ad-hoc build 0.1.240 (241) did a real flash on the same iPod. The log shows `Wrote and verified 112640 bytes in 33 range(s)`, with no fault. The app had an ad-hoc signature. The owner confirmed that Full Disk Access was off for that app.

## No fallback to root

The app has no fallback to a root process, for these reasons:

- A root process caused issues #2 and #3.
- macOS blocks a root process without Full Disk Access. A user with `EPERM` from `authopen` probably has the same block on that path.
- A second write path needs its own tests on a real iPod.

`authopen` fails at the open, before the first write. Thus the app has two small steps: it tries the whole disk if the slice fails, and it mounts the iPod again if the write cannot start.

## What is not known

1. Does the result stay the same on other versions of macOS? The test used macOS 27.2. The reports are from macOS 15.7.7.
2. Does a Windows-format iPod have a firmware slice? If it has none, the app opens the whole disk after the unmount. This open operates on a Mac-format iPod, but no write used this path on a real iPod.
3. Does the prompt offer Touch ID?
4. Does a standard user operate the app with the name of an administrator?

## Sources

- <https://tech.dreamleaves.org/posts/how-to-write-to-dev-rdiskx-without-root-a-look-at-macos-authopen/>
- <https://developer.apple.com/forums/thread/777577>
- `man authopen`
