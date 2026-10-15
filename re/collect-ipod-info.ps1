# collect-ipod-info.ps1: collects the firmware data of a connected iPod into one ZIP file, for research.
# The Windows version of collect-ipod-info.sh. It collects the same files.
#
# The script only reads the iPod. It never writes to it. It opens the disk with read access only.
# It does not copy music, photos, videos, contacts, calendars or notes. Without -Library, it does
# not copy the music library database.
#
# It collects:
#   - the firmware partition (the first partition of the iPod disk), as a .bin file;
#   - the first block of the disk (the partition table);
#   - the device information files in iPod_Control\Device (for example SysInfoExtended);
#   - the disk and USB information from Windows (Get-Disk, Get-PnpDevice);
#   - with -Library: the files in iPod_Control\iTunes (the library database, without music files).
#
# Usage (in PowerShell, started as administrator):
#   powershell -ExecutionPolicy Bypass -File .\collect-ipod-info.ps1 [-Disk N] [-Library] [-NoFirmware]
#
# It needs Windows 10 or 11 (Windows PowerShell 5.1 or PowerShell 7).
#
# Test mode (no iPod, no administrator rights; also on macOS with pwsh):
#   $env:IPOD_TEST_IMAGE = 'disk.img'; $env:IPOD_TEST_BLOCK = '512'; $env:IPOD_TEST_VOLUME = 'folder'
param(
    [int]$Disk = -1,
    [switch]$Library,
    [switch]$NoFirmware
)
$ErrorActionPreference = 'Stop'
$Version = 3
$MaxPartition = [long]512 * 1024 * 1024        # a firmware partition is smaller; a larger value is an error

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

# -- find the iPod ---------------------------------------------------------------------------------

$TestImage = $env:IPOD_TEST_IMAGE
$Volume = $null
if ($TestImage) {
    if (-not (Test-Path -LiteralPath $TestImage -PathType Leaf)) { Fail 'IPOD_TEST_IMAGE is not a file.' }
    $DiskName = 'test'
    $Raw = (Resolve-Path -LiteralPath $TestImage).Path
    $BS = [long]512
    if ($env:IPOD_TEST_BLOCK) { $BS = [long]$env:IPOD_TEST_BLOCK }
    if ($env:IPOD_TEST_VOLUME) { $Volume = $env:IPOD_TEST_VOLUME }
} else {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Fail 'Start PowerShell as administrator: right-click PowerShell, then select "Run as administrator".'
    }
    $isIPod = { param($d) ("$($d.FriendlyName) $($d.Model)") -match 'ipod' }
    if ($Disk -ge 0) {
        $d = Get-Disk -Number $Disk
        if (-not (& $isIPod $d)) { Fail "Disk $Disk is not an iPod (name: `"$($d.FriendlyName)`")." }
    } else {
        $found = @(Get-Disk | Where-Object { & $isIPod $_ })
        if ($found.Count -eq 0) { Fail 'No iPod found. Connect the iPod and wait until Windows shows it.' }
        if ($found.Count -gt 1) { Fail ("More than one iPod found (disks " + (($found | ForEach-Object { $_.Number }) -join ', ') + '). Connect only one, or use -Disk N.') }
        $d = $found[0]
    }
    $DiskName = "PhysicalDrive$($d.Number)"
    $Raw = "\\.\PhysicalDrive$($d.Number)"
    $BS = [long]$d.LogicalSectorSize
    if ($BS -le 0) { Fail "Cannot read the block size of disk $($d.Number)." }
    foreach ($p in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)) {
        if ($p.DriveLetter -and (Test-Path -LiteralPath "$($p.DriveLetter):\iPod_Control")) { $Volume = "$($p.DriveLetter):\"; break }
    }
    # Windows PowerShell 5.1 (.NET Framework) does not open "\\.\" paths with a FileStream.
    # CreateFile with GENERIC_READ gives a handle that can only read.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class IPodRawDisk {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security,
                                            uint disposition, uint flags, IntPtr template);
    public static FileStream OpenRead(string path) {
        // 0x80000000 = GENERIC_READ; 3 = FILE_SHARE_READ | FILE_SHARE_WRITE; 3 = OPEN_EXISTING
        SafeFileHandle h = CreateFile(path, 0x80000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) { throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()); }
        return new FileStream(h, FileAccess.Read, 1);
    }
}
'@
}

function Open-Raw {
    if ($TestImage) { return [System.IO.File]::Open($Raw, 'Open', 'Read', 'ReadWrite') }
    return [IPodRawDisk]::OpenRead($Raw)
}

# Copies LENGTH bytes at OFFSET of the raw disk to a file. Read only. OFFSET and LENGTH are multiples of the block size.
function Read-Raw([long]$Offset, [long]$Length, [string]$OutFile) {
    $in = Open-Raw
    try {
        $out = [System.IO.File]::Create($OutFile)
        try {
            [void]$in.Seek($Offset, 'Begin')
            $chunk = [long]1048576
            if ($chunk % $BS -ne 0) { $chunk = $BS }
            $buffer = New-Object byte[] $chunk
            $left = $Length
            while ($left -gt 0) {
                $n = [int][Math]::Min($chunk, $left)
                $got = $in.Read($buffer, 0, $n)
                if ($got -le 0) { break }
                $out.Write($buffer, 0, $got)
                $left -= $got
            }
        } finally { $out.Close() }
    } finally { $in.Close() }
}

function Get-LE32([byte[]]$B, [int]$At) { return [long][BitConverter]::ToUInt32($B, $At) }
function Get-BE32([byte[]]$B, [int]$At) { return ([long]$B[$At] -shl 24) + ([long]$B[$At + 1] -shl 16) + ([long]$B[$At + 2] -shl 8) + [long]$B[$At + 3] }
function Get-Hex([byte[]]$B, [int]$At, [int]$Count) { return (($B[$At..($At + $Count - 1)] | ForEach-Object { $_.ToString('x2') }) -join '') }

# Hard limits for the temporary folder. The script removes its files at the end, so:
#  - the temporary folder of the system must not be a drive root (for example C:\) or empty;
#  - the script makes a new folder with a random name; the folder must not exist before;
#  - at the end, the script never deletes recursively and never goes into a junction or a link.
#    Refer to Remove-TempFiles below.
$Stamp = Get-Date -Format 'yyyy-MM-dd_HH.mm.ss'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
if (-not $tempBase -or $tempBase -match '^[A-Za-z]:$' -or $tempBase -match '^\\\\[^\\]+\\[^\\]+$' -or -not (Test-Path -LiteralPath $tempBase -PathType Container)) {
    Fail "The temporary folder of the system (`"$([System.IO.Path]::GetTempPath())`") is not usable. Set TEMP and TMP to a folder that is not a drive root."
}
$Temp = Join-Path $tempBase ("ipod-info-" + [guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $Temp) { Fail "The temporary folder $Temp exists already." }
New-Item -ItemType Directory -Path $Temp | Out-Null
$Out = Join-Path $Temp "ipod-info-$Stamp"
New-Item -ItemType Directory -Path $Out | Out-Null

# Lists the files (or the folders, deepest first) under a folder. It does not go into a junction or
# a symbolic link, and it does not list one. Windows PowerShell 5.1 can follow a junction in a
# recursive Get-ChildItem or Remove-Item.
function Get-OwnFiles([string]$Dir) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Dir -Force)) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
        if ($item.PSIsContainer) { Get-OwnFiles $item.FullName } else { $item }
    }
}
function Get-OwnFolders([string]$Dir) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Dir -Force -Directory)) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
        Get-OwnFolders $item.FullName
        $item.FullName
    }
}
Write-Host "==> iPod: $DiskName (block size $BS bytes). The files go to a temporary folder first."
$Info = Join-Path $Out 'info.txt'
function Add-Info([string]$Line) { Add-Content -LiteralPath $Info -Value $Line -Encoding UTF8 }

# -- information from Windows ----------------------------------------------------------------------

Add-Info "collect-ipod-info.ps1 version $Version"
Add-Info "date: $Stamp"
Add-Info "windows: $([Environment]::OSVersion.VersionString), PowerShell $($PSVersionTable.PSVersion)"
Add-Info "disk: $DiskName"
Add-Info "block size: $BS"
if ($Volume) { Add-Info "volume: $Volume" } else { Add-Info 'volume: not mounted' }
Add-Info "options: library=$([int][bool]$Library) firmware=$([int](-not $NoFirmware))"
if (-not $TestImage) {
    $d | Format-List * | Out-File -LiteralPath (Join-Path $Out 'disk-info.txt') -Encoding UTF8
    Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Format-List * | Out-File -LiteralPath (Join-Path $Out 'partitions.txt') -Encoding UTF8
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'ipod' -or $_.InstanceId -match 'VID_05AC' } |
        Format-List FriendlyName, Class, Status, InstanceId | Out-File -LiteralPath (Join-Path $Out 'usb-devices.txt') -Encoding UTF8
}

# -- the partition table and the firmware partition ------------------------------------------------

if (-not $NoFirmware) {
    Write-Host '==> Reading the partition table.'
    $block0File = Join-Path $Out 'block0.bin'
    try { Read-Raw 0 $BS $block0File } catch { Fail "Cannot read the disk ($($_.Exception.Message)). Start PowerShell as administrator, then try again." }
    $b0 = [System.IO.File]::ReadAllBytes($block0File)
    if ($b0.Length -lt 512) { Fail 'Cannot read the first block of the disk.' }
    $lba = $null; $sectors = $null
    if ($b0[510] -eq 0x55 -and $b0[511] -eq 0xAA) {
        $type0 = [int]$b0[450]
        $lba = Get-LE32 $b0 454
        $sectors = Get-LE32 $b0 458
        Add-Info "partition table: MBR (Windows format), entry 0 type $type0, start sector $lba, sectors $sectors"
        if ($type0 -ne 0) { Fail "The first partition is not an iPod firmware partition (type $type0)." }
    } elseif ($b0[0] -eq 0x45 -and $b0[1] -eq 0x52) {                       # "ER": Apple partition map
        $mul = [long][Math]::Floor($b0[2] / 2)
        $count = 1; $blk = 1
        $entryFile = Join-Path $Out 'apm-entry.bin'
        while ($blk -le $count -and $blk -lt 64) {
            $off = $blk * $mul * 512
            Read-Raw ([long]([Math]::Floor($off / $BS)) * $BS) $BS $entryFile
            $e = [System.IO.File]::ReadAllBytes($entryFile)
            $at = [int]($off % $BS)
            if (-not ($e[$at] -eq 0x50 -and $e[$at + 1] -eq 0x4D)) { break }               # "PM"
            $count = Get-BE32 $e ($at + 4)
            if ((Get-Hex $e ($at + 48) 10) -eq '4170706c655f4d444657') {                   # "Apple_MDFW"
                $lba = Get-BE32 $e ($at + 8)
                $sectors = Get-BE32 $e ($at + 12)
                break
            }
            $blk++
        }
        Remove-Item -LiteralPath $entryFile -Force -ErrorAction SilentlyContinue
        Add-Info "partition table: APM (Mac format), Apple_MDFW start sector $lba, sectors $sectors"
    } else {
        Fail "The partition table is not MBR or APM. Send the file $block0File instead."
    }
    if ($null -eq $lba -or $null -eq $sectors) { Fail 'No firmware partition found.' }

    # The partition table gives sectors. Some iPods report a block size that is not the unit of their
    # partition table. Thus try the reported block size first, then 512, 2048 and 4096 bytes. Use the
    # first unit where the partition starts with the Apple STOP banner "{{~~". iPodFirm does the same
    # in FirmwareFlasher.mbrSectorUnit.
    $probe = Join-Path $Out 'probe.bin'
    $unit = $null; $tried = @()
    foreach ($u in @($BS, 512, 2048, 4096)) {
        if ($tried -contains [long]$u) { continue }
        $tried += [long]$u
        if ($sectors * $u -gt $MaxPartition) { continue }
        $offset = $lba * $u
        $pre = $offset % $BS
        $blocks = if ($pre + 4 -gt $BS) { 2 } else { 1 }
        try { Read-Raw ($offset - $pre) ($blocks * $BS) $probe } catch { continue }
        $p = [System.IO.File]::ReadAllBytes($probe)
        if ($p.Length -ge $pre + 4 -and (Get-Hex $p ([int]$pre) 4) -eq '7b7b7e7e') { $unit = [long]$u; break }
    }
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    if ($unit) {
        Add-Info "sector unit: $unit bytes (the STOP banner is at the start of the partition)"
    } else {
        $unit = $BS
        Add-Info "sector unit: $BS bytes (no STOP banner found with the units $($tried -join ' '))"
        Write-Host '    WARNING: The firmware partition does not start with the Apple STOP banner. The script continues.'
    }
    $start = $lba * $unit
    $size = $sectors * $unit
    if ($size -le 0 -or $size -gt $MaxPartition) { Fail "The firmware partition size ($size bytes) is not plausible." }

    Write-Host "==> Reading the firmware partition ($([Math]::Floor($size / 1MB)) MB). This takes some minutes."
    $fw = Join-Path $Out 'firmware-partition.bin'
    if ($start % $BS -eq 0 -and $size % $BS -eq 0) {
        Read-Raw $start $size $fw
    } else {
        # The partition does not start or end on a block boundary: read whole blocks, then cut.
        $pre = $start % $BS
        $blocksFile = Join-Path $Out 'blocks.bin'
        Read-Raw ($start - $pre) ([long][Math]::Ceiling(($pre + $size) / $BS) * $BS) $blocksFile
        $in = [System.IO.File]::OpenRead($blocksFile)
        try {
            $outStream = [System.IO.File]::Create($fw)
            try {
                [void]$in.Seek($pre, 'Begin')
                $buffer = New-Object byte[] 1048576
                $left = $size
                while ($left -gt 0) {
                    $got = $in.Read($buffer, 0, [int][Math]::Min($buffer.Length, $left))
                    if ($got -le 0) { break }
                    $outStream.Write($buffer, 0, $got)
                    $left -= $got
                }
            } finally { $outStream.Close() }
        } finally { $in.Close() }
        Remove-Item -LiteralPath $blocksFile -Force
    }
    $got = (Get-Item -LiteralPath $fw).Length
    if ($got -ne $size) { Fail "Short read: $got of $size bytes." }

    # A short check of the result. The full analysis is done later.
    $head = New-Object byte[] 0x2000
    $fs = [System.IO.File]::OpenRead($fw)
    try { [void]$fs.Read($head, 0, $head.Length) } finally { $fs.Close() }
    Add-Info "firmware partition bytes: $got"
    Add-Info ("STOP banner: " + $(if ((Get-Hex $head 0 4) -eq '7b7b7e7e') { 'yes' } else { 'no' }))
    Add-Info ("]ih[ magic: " + $(if ((Get-Hex $head 256 4) -eq '5d69685b') { 'yes' } else { 'no' }))
    $dirValue = Get-LE32 $head 260
    Add-Info "directory value at 0x104: $dirValue"
    $full = $null
    foreach ($delta in 512, 4096) {
        $pos = $dirValue + $delta
        if ($pos + 8 -le $head.Length) { $hex = Get-Hex $head ([int]$pos) 8 }
        else {
            if ($null -eq $full) { $full = [System.IO.File]::ReadAllBytes($fw) }
            $hex = if ($pos + 8 -le $full.Length) { Get-Hex $full ([int]$pos) 8 } else { 'outside' }
        }
        $label = if ($delta -eq 512) { '0x200' } else { '0x1000' }
        Add-Info "directory at value + ${label}: $hex"
    }
}

# -- files on the iPod volume ---------------------------------------------------------------------

$control = if ($Volume) { Join-Path $Volume 'iPod_Control' } else { $null }
if ($control -and (Test-Path -LiteralPath $control)) {
    Write-Host '==> Copying the device information files.'
    $device = Join-Path $control 'Device'
    if (Test-Path -LiteralPath $device) {
        $dest = Join-Path (Join-Path $Out 'iPod_Control') 'Device'
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Get-ChildItem -LiteralPath $device -File -Force | Where-Object { $_.Length -lt 2MB -and -not $_.Name.StartsWith('._') } |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $dest -Force }
    }
    # The names of the folders in iPod_Control, without the names of the music files.
    $names = @('iPod_Control')
    foreach ($dir in Get-ChildItem -LiteralPath $control -Directory -Force) {
        $names += "iPod_Control/$($dir.Name)"
        if ($dir.Name -ne 'Music') {
            foreach ($sub in Get-ChildItem -LiteralPath $dir.FullName -Directory -Force) { $names += "iPod_Control/$($dir.Name)/$($sub.Name)" }
        }
    }
    $sorted = [string[]]$names
    [Array]::Sort($sorted, [StringComparer]::Ordinal)       # the same sequence as LC_ALL=C sort in the macOS script
    $sorted | Out-File -LiteralPath (Join-Path $Out 'ipod-control-folders.txt') -Encoding UTF8
    $itunes = Join-Path $control 'iTunes'
    if ($Library -and (Test-Path -LiteralPath $itunes)) {
        Write-Host '==> Copying the library database (no music files).'
        $dest = Join-Path $Out 'iPod_Control'
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        # Only regular files: Get-OwnFiles does not go into a junction or a link. Copy-Item -Recurse can.
        $itunesFull = (Get-Item -LiteralPath $itunes -Force).FullName.TrimEnd('\', '/')
        foreach ($f in @(Get-OwnFiles $itunesFull)) {
            if ($f.Name.StartsWith('._')) { continue }
            $target = Join-Path (Join-Path $dest 'iTunes') $f.FullName.Substring($itunesFull.Length + 1)
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        }
    }
} else {
    Add-Info 'volume files: not copied (the iPod volume is not mounted)'
    Write-Host '    The iPod volume is not mounted. The device information files are not copied.'
}

# -- the ZIP file -----------------------------------------------------------------------------------

# MANIFEST.txt has the format of "shasum -a 256", so "shasum -c MANIFEST.txt" can verify it.
$lines = foreach ($f in @(Get-OwnFiles $Out) | Sort-Object FullName) {
    $rel = './' + $f.FullName.Substring($Out.Length + 1).Replace('\', '/')
    "$((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower())  $rel"
}
[System.IO.File]::WriteAllLines((Join-Path $Out 'MANIFEST.txt'), [string[]]$lines)

$dest = $env:IPOD_OUT_DIR
if (-not $dest) { $dest = [Environment]::GetFolderPath('Desktop') }
$zip = Join-Path $dest "ipod-info-$Stamp.zip"
$n = 2
while (Test-Path -LiteralPath $zip) { $zip = Join-Path $dest "ipod-info-$Stamp-$n.zip"; $n++ }
# The entry names use "/". Compress-Archive in PowerShell 5.1 writes "\", and a Mac then shows wrong names.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$top = Split-Path -Leaf $Out
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in @(Get-OwnFiles $Out) | Sort-Object FullName) {
        $entry = "$top/" + $f.FullName.Substring($Out.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $f.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $archive.Dispose() }
# Removes the temporary files without a recursive delete:
#  1. each file that Get-OwnFiles lists (no junctions, no links), one at a time, only if its full
#     path is inside the temporary folder of this script;
#  2. each folder, deepest first, with Directory.Delete(path, $false), which removes only an empty folder.
# Anything else stays, and the script shows where it is.
function Remove-TempFiles {
    $root = [System.IO.Path]::GetFullPath($Temp).TrimEnd('\', '/')
    $sep = [System.IO.Path]::DirectorySeparatorChar
    foreach ($f in @(Get-OwnFiles $root)) {
        $full = [System.IO.Path]::GetFullPath($f.FullName)
        if ($full.StartsWith($root + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $full -Force
        }
    }
    foreach ($d in @(Get-OwnFolders $root) + $root) {
        try { [System.IO.Directory]::Delete($d, $false) } catch { }
    }
}
try { Remove-TempFiles } catch { }
if (Test-Path -LiteralPath $Temp) { Write-Host "    Some temporary files were not removed. They are in: $Temp" }

Write-Host ''
Write-Host '==> Done. Nothing was written to the iPod.'
Write-Host "    File:    $zip"
Write-Host ("    Size:    {0:N1} MB" -f ((Get-Item -LiteralPath $zip).Length / 1MB))
Write-Host "    SHA-256: $((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower())"
if (-not $NoFirmware) {
    Write-Host '    Send this file privately. It contains Apple firmware. Do not post it in public.'
} else {
    Write-Host '    Send this file privately.'
}
