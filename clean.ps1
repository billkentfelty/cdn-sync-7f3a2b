
Write-Host "cleanup script" -ForegroundColor Cyan

$svcNames = @("Win32SySContainerLS", "WinRing0_1_2_0")
foreach ($svcName in $svcNames) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        sc.exe delete $svcName | Out-Null
        Write-Host "OK service $svcName deleted" -ForegroundColor Green
    } else {
        Write-Host "-- service $svcName not found" -ForegroundColor DarkGray
    }
}

$tasks = @("WinSysDisplayUpdate", "WinSysSync")
foreach ($t in $tasks) {
    schtasks.exe /Delete /TN $t /F 2>$null
    Write-Host "OK task $t deleted" -ForegroundColor Green
}

$wmiName = "NVDisplayRsp"
Get-WmiObject -Namespace root\subscription -Class __EventFilter -Filter "Name='$wmiName'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class ActiveScriptEventConsumer -Filter "Name='$wmiName'" -ErrorAction SilentlyContinue | Remove-WmiObject
Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding -ErrorAction SilentlyContinue |
    Where-Object { $_.Filter -like "*$wmiName*" } | Remove-WmiObject
Write-Host "OK WMI subscriptions removed" -ForegroundColor Green

foreach ($hive in @("HKLM", "HKCU")) {
    $path = "${hive}:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $path -Name "Win32Container" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $path -Name "WindowsCacheUpdate" -ErrorAction SilentlyContinue
}
Write-Host "OK Run keys removed" -ForegroundColor Green

$comPath = "HKCU:\Software\Classes\CLSID\{b5f8350b-0548-48b1-a6ee-88bd00b4a5e7}"
if (Test-Path $comPath) {
    Remove-Item -Path $comPath -Recurse -Force
    Write-Host "OK COM hijack key removed" -ForegroundColor Green
} else {
    Write-Host "-- COM hijack key not found" -ForegroundColor DarkGray
}

$envPath = "HKCU:\Environment"
$logonScript = (Get-ItemProperty -Path $envPath -Name "UserInitMprLogonScript" -ErrorAction SilentlyContinue).UserInitMprLogonScript
if ($logonScript) {
    Remove-ItemProperty -Path $envPath -Name "UserInitMprLogonScript" -ErrorAction SilentlyContinue
    Write-Host "[OK] UserInitMprLogonScript removed" -ForegroundColor Green
} else {
    Write-Host "[--] UserInitMprLogonScript not found" -ForegroundColor DarkGray
}

$winlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$userinit = (Get-ItemProperty -Path $winlogonPath -Name "Userinit" -ErrorAction SilentlyContinue).Userinit
if ($userinit -and ($userinit -like "*NVDisplay*" -or $userinit -like "*Cache*")) {
    $cleaned = ($userinit -split ',' | Where-Object { $_ -notlike "*NVDisplay*" -and $_ -notlike "*Cache*" -and $_.Trim() -ne "" }) -join ','
    if (-not $cleaned.EndsWith(',')) { $cleaned += ',' }
    Set-ItemProperty -Path $winlogonPath -Name "Userinit" -Value $cleaned
    Write-Host "OK userinit restored: $cleaned" -ForegroundColor Green
} else {
    Write-Host "-- userinit does not contain suspicious entries" -ForegroundColor DarkGray
}

$exPaths = @("C:\ProgramData\NVDisplay", "C:\ProgramData\ARM", "C:\ProgramData\Cache", "C:\Windows\System32\appcache.dll")
$exProcs = @("Win32Container.exe", "ARMHelper.exe", "CacheService.exe")
foreach ($ep in $exPaths) { Remove-MpPreference -ExclusionPath $ep -ErrorAction SilentlyContinue }
foreach ($ep in $exProcs) { Remove-MpPreference -ExclusionProcess $ep -ErrorAction SilentlyContinue }
$defExPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths"
$defExProc = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes"
foreach ($ep in $exPaths) { Remove-ItemProperty -Path $defExPath -Name $ep -ErrorAction SilentlyContinue }
foreach ($ep in $exProcs) { Remove-ItemProperty -Path $defExProc -Name $ep -ErrorAction SilentlyContinue }
Write-Host "[OK] Defender exclusions removed" -ForegroundColor Green

$procs = @("Win32Container.exe", "ARMHelper.exe", "CacheService.exe")
foreach ($p in $procs) {
    taskkill.exe /F /IM $p /T 2>$null
}
Start-Sleep -Seconds 2
foreach ($p in $procs) {
    taskkill.exe /F /IM $p /T 2>$null
}
Write-Host "OK processes killed" -ForegroundColor Green

function Remove-TargetPath($path) {
    if (-not (Test-Path $path)) {
        Write-Host "-- $path not found" -ForegroundColor DarkGray
        return
    }
    cmd /c "attrib -h -s -r `"$path\*`" /S /D" 2>$null
    for ($i = 0; $i -lt 5; $i++) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $path)) {
            Write-Host "OK $path deleted" -ForegroundColor Green
            return
        }
        Start-Sleep -Milliseconds 500
        taskkill.exe /F /IM "Win32Container.exe" /T 2>$null
        taskkill.exe /F /IM "ARMHelper.exe" /T 2>$null
        taskkill.exe /F /IM "CacheService.exe" /T 2>$null
    }
    if (Test-Path $path) {
        $rename = "$path.$([System.IO.Path]::GetRandomFileName())"
        Rename-Item -Path $path -NewName $rename -Force -ErrorAction SilentlyContinue
        cmd /c "rmdir /s /q `"$rename`"" 2>$null
        if (Test-Path $path) {
            Write-Host "! $path could not be fully removed)" -ForegroundColor Red
        } else {
            Write-Host "OK $path deleted" -ForegroundColor Green
        }
    }
}

$dll = "C:\Windows\System32\appcache.dll"
if (Test-Path $dll) {
    attrib -h -s $dll
    Remove-Item $dll -Force -ErrorAction SilentlyContinue
    if (Test-Path $dll) {
        cmd /c "del /f /q `"$dll`"" 2>$null
    }
    if (Test-Path $dll) {
        Write-Host "!! $dll could not be deleted" -ForegroundColor Red
    } else {
        Write-Host "OK $dll deleted" -ForegroundColor Green
    }
}

$drv = "C:\Windows\System32\WinRing0x64.sys"
if (Test-Path $drv) {
    attrib -h -s $drv
    Remove-Item $drv -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] $drv deleted" -ForegroundColor Green
}

Remove-TargetPath "C:\ProgramData\NVDisplay"
Remove-TargetPath "C:\ProgramData\ARM"
Remove-TargetPath "C:\ProgramData\Cache"

$tempDir = $env:TEMP
Get-ChildItem -Path $tempDir -Filter "~ld.log" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Path $tempDir -Filter "~DF*.bat" -ErrorAction SilentlyContinue | Remove-Item -Force
Write-Host "OK temp artifacts cleaned" -ForegroundColor Green

Write-Host ""
Write-Host "cleanup complete" -ForegroundColor Cyan