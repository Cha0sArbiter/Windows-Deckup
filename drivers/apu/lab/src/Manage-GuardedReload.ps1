param(
    [ValidateSet('Prepare','Start','Watch','Keep')][string]$Mode='Prepare',
    [ValidatePattern('^$|^[a-fA-F0-9-]{36}$')][string]$Nonce=''
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$guardRoot=Join-Path $projectRoot 'guarded-reload'
$taskName='SteamDeckDriverLab-GuardedReload'
$hardwareId='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE'
$candidateKernel='AE975BBB56282BE1471B9A91407F0155C087B619F99D2731D4E7989720522152'
$candidateConfig='7EE54354831BBF267C590636FFFFD95FCA91FF5455578151FA657BD5F9162717'
$prototypeKernel='E1B4DBFB807A59971BFC90E8139E35F96B4ADEDFD773695DBDCA5568B83D1ADF'
$applyScript=Join-Path $PSScriptRoot 'Apply-ConfigTrial.ps1'
$powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Mode -ne 'Keep' -and -not $admin) { throw 'Windows administrator rights are required for recovery preparation and driver switching.' }

function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Write-Json([string]$Path,$Value) {
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $previous=$temporary+'.previous'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    try {
        for ($attempt=0; $attempt -lt 10; $attempt++) {
            try {
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,$previous) } else { [IO.File]::Move($temporary,$Path) }
                return
            } catch [IO.IOException] {
                if ($attempt -eq 9) { throw }
                Start-Sleep -Milliseconds 25
            }
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($previous)) { [IO.File]::Delete($previous) }
    }
}
function New-ReloadDecision {
    param([string]$Path,[string]$Token,[ValidateSet('Keep','Rollback')][string]$Decision,[datetime]$DeadlineUtc,[datetime]$NowUtc=[datetime]::UtcNow)
    if ($Decision -eq 'Keep' -and $NowUtc -ge $DeadlineUtc) { throw 'The acknowledgment deadline has expired.' }
    if ($Decision -eq 'Rollback' -and $NowUtc -lt $DeadlineUtc) { throw 'Recovery cannot begin before the deadline.' }
    if ([IO.File]::Exists($Path)) {
        if ((Read-Json $Path).Nonce -ne $Token) { throw 'Recovery decision belongs to another trial.' }
        return $false
    }
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $value=[PSCustomObject]@{Nonce=$Token; Decision=$Decision; DecidedUtc=$NowUtc.ToUniversalTime().ToString('o')}
        [IO.File]::WriteAllText($temporary,($value | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$Path)
        return $true
    } catch [IO.IOException] {
        if (-not [IO.File]::Exists($Path)) { throw }
        return $false
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Initialize-Native {
    if (-not ('GuardedDeckNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GuardedDeckNative {
    [DllImport("ntdll.dll")] public static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returnLength);
    [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
}
'@
    }
}
function Read-CodeIntegrity {
    Initialize-Native
    $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer,8)
        $length=0
        if ([GuardedDeckNative]::NtQuerySystemInformation(103,$buffer,8,[ref]$length) -ne 0) { throw 'Could not query Code Integrity.' }
        $options=[Runtime.InteropServices.Marshal]::ReadInt32($buffer,4)
        [PSCustomObject]@{Options=$options; TestSigningActive=(($options -band 2) -ne 0)}
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
}
function Read-Gpu {
    $devices=@(Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like ($hardwareId+'\*') })
    if ($devices.Count -ne 1) { throw 'Expected exactly one LCD Deck GPU.' }
    $values=@{}
    Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId -KeyName 'DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_Service' | ForEach-Object { $values[$_.KeyName]=$_.Data }
    [PSCustomObject]@{InstanceId=$devices[0].InstanceId; ProblemCode=[int]$values['DEVPKEY_Device_ProblemCode']; Inf=[string]$values['DEVPKEY_Device_DriverInfPath']; Version=[string]$values['DEVPKEY_Device_DriverVersion']; Service=[string]$values['DEVPKEY_Device_Service']}
}
function Read-SelectedKernelHash($Gpu) {
    $image=[string](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$Gpu.Service) -Name ImagePath).ImagePath
    $path=[Environment]::ExpandEnvironmentVariables($image).Trim('"')
    if ($path.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)) { $path=Join-Path $env:SystemRoot $path.Substring(12) }
    if ($path.StartsWith('\??\')) { $path=$path.Substring(4) }
    $path=[IO.Path]::GetFullPath($path)
    $storeRoot=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository')).TrimEnd('\')+'\'
    if (-not $path.StartsWith($storeRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -ne 'amdkmdag.sys') { throw 'Unexpected selected GPU kernel path.' }
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Assert-Deck {
    $computer=Get-CimInstance Win32_ComputerSystem
    if ($computer.Manufacturer -ne 'Valve' -or $computer.Model -ne 'Jupiter') { throw 'This test is restricted to the LCD Deck.' }
    if (-not (Read-CodeIntegrity).TestSigningActive) { throw 'Test Mode must remain on throughout this guarded trial.' }
}
function Assert-Package($Manifest) {
    $absoluteRoot=[IO.Path]::GetFullPath($Manifest.PackageDirectory).TrimEnd('\')+'\'
    foreach ($file in $Manifest.Files) {
        $path=[IO.Path]::GetFullPath((Join-Path $absoluteRoot $file.Path))
        if (-not $path.StartsWith($absoluteRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Package manifest escapes its directory.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw "Package hash mismatch: $($file.Path)" }
    }
}
function Assert-Scripts($Plan) {
    if ((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -ne $Plan.WatchdogScriptSHA256 -or (Get-FileHash -LiteralPath $applyScript -Algorithm SHA256).Hash -ne $Plan.ApplyScriptSHA256) { throw 'A prepared recovery script changed.' }
    if ($Plan.TaskName -ne $taskName -or $Plan.TimeoutSeconds -ne 180) { throw 'Unexpected recovery plan.' }
}
function Write-Status([string]$Status,$Details=$null) {
    Write-Json (Join-Path $trialDirectory 'watchdog-status.json') ([PSCustomObject]@{Nonce=$Nonce; Status=$Status; HeartbeatUtc=[datetime]::UtcNow.ToString('o'); ProcessId=$PID; Identity=$identity.User.Value; Details=$Details})
}
function Retire-Task {
    Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Mode='Idle'})
    $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task -and $task.Actions.Arguments -like ('*'+$Nonce+'*')) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
}

if ($Mode -eq 'Prepare') {
    Assert-Deck
    $gpu=Read-Gpu
    if ($gpu.Inf -ne 'oem50.inf' -or $gpu.Version -ne '32.0.21043.21001' -or $gpu.ProblemCode -ne 0 -or (Read-SelectedKernelHash $gpu) -ne $prototypeKernel) { throw 'The working prototype must be healthy before preparing this test.' }
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { throw 'A guarded reload task already exists; inspect it before creating another.' }
    $candidate=Read-Json (Join-Path $projectRoot 'private-config-install\signed-config-package.json')
    $prototype=Read-Json (Join-Path $projectRoot 'private-driver\signed-package.json')
    if ($candidate.KernelModified -or $candidate.KernelSHA256 -ne $candidateKernel -or $candidate.ConfigurationSHA256 -ne $candidateConfig -or $prototype.KernelSHA256 -ne $prototypeKernel) { throw 'Unexpected candidate or fallback kernel/configuration.' }
    Assert-Package $candidate
    Assert-Package $prototype
    foreach ($pair in @(@('oem56.inf',(Join-Path $candidate.PackageDirectory $candidate.MainInf)),@('oem57.inf',(Join-Path $candidate.PackageDirectory $candidate.ExtensionInf)),@('oem50.inf',(Join-Path $prototype.PackageDirectory $prototype.MainInf)))) {
        if ((Get-FileHash -LiteralPath (Join-Path $env:SystemRoot ('INF\'+$pair[0])) -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash) { throw 'Expected candidate/fallback package is not staged.' }
    }
    $Nonce=[guid]::NewGuid().ToString()
    $trialDirectory=Join-Path $guardRoot $Nonce
    New-Item -ItemType Directory -Path $trialDirectory -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'config-trial-state.json') -Destination (Join-Path $trialDirectory 'state-before-test.json')
    $plan=[PSCustomObject]@{Nonce=$Nonce; TaskName=$taskName; TimeoutSeconds=180; PreparedUtc=[datetime]::UtcNow.ToString('o'); ApplyScriptSHA256=(Get-FileHash -LiteralPath $applyScript -Algorithm SHA256).Hash; WatchdogScriptSHA256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash; CandidateInf='oem56.inf'; PrototypeInf='oem50.inf'; CandidateKernelSHA256=$candidateKernel; CandidateConfigurationSHA256=$candidateConfig; PrototypeKernelSHA256=$prototypeKernel; CurrentGpu=$gpu; CodeIntegrity=(Read-CodeIntegrity); AutoRecoveryRequestsRestart=$true}
    Write-Json (Join-Path $trialDirectory 'plan.json') $plan
    Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Mode='SelfTest'})
    Write-Json (Join-Path $guardRoot 'active.json') ([PSCustomObject]@{Nonce=$Nonce; Directory=$trialDirectory; TaskName=$taskName})
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode Watch -Nonce '+$Nonce
    $action=New-ScheduledTaskAction -Execute $powershell -Argument $arguments
    $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Trigger (New-ScheduledTaskTrigger -AtStartup) -Description 'One guarded Deck graphics-driver reload; restores the verified prototype after 180 seconds without acknowledgment.' | Out-Null
    Start-ScheduledTask -TaskName $taskName
    $stopAt=[datetime]::UtcNow.AddSeconds(45)
    $selfTestPath=Join-Path $trialDirectory 'self-test.json'
    while (-not (Test-Path -LiteralPath $selfTestPath)) {
        if ([datetime]::UtcNow -ge $stopAt) { throw 'The elevated recovery task did not pass its self-test in time.' }
        Start-Sleep -Seconds 1
    }
    $selfTest=Read-Json $selfTestPath
    if (-not $selfTest.Passed -or $selfTest.Nonce -ne $Nonce -or $selfTest.Identity -ne 'S-1-5-18') { throw 'The recovery task self-test failed.' }
    Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Mode='Idle'})
    Write-Status 'Ready' $selfTest
    Write-Output 'Guarded live reload is ready. The current prototype has not been changed. The 180-second recovery timer starts at the driver switch.'
    exit 0
}

if (-not $Nonce) { $Nonce=[string](Read-Json (Join-Path $guardRoot 'active.json')).Nonce }
$parsedNonce=[guid]::Empty
if (-not [guid]::TryParse($Nonce,[ref]$parsedNonce)) { throw 'Invalid trial identifier.' }
$trialDirectory=Join-Path $guardRoot $Nonce
$plan=Read-Json (Join-Path $trialDirectory 'plan.json')
if ($plan.Nonce -ne $Nonce) { throw 'Trial identifier does not match the recovery plan.' }
Assert-Scripts $plan

if ($Mode -eq 'Keep') {
    $start=Read-Json (Join-Path $trialDirectory 'reload-start.json')
    if ($start.Nonce -ne $Nonce -or $start.TimeoutSeconds -ne 180) { throw 'The guarded reload has not started.' }
    $deadline=[datetime]::Parse($start.StartedUtc).ToUniversalTime().AddSeconds(180)
    $saved=New-ReloadDecision -Path (Join-Path $trialDirectory 'decision.json') -Token $Nonce -Decision Keep -DeadlineUtc $deadline
    $decision=Read-Json (Join-Path $trialDirectory 'decision.json')
    if ($decision.Decision -ne 'Keep') { throw 'Automatic recovery has already started; it cannot be canceled now.' }
    Write-Output 'Acknowledged: keep the configuration-only candidate. The watchdog will retire its recovery task.'
    exit 0
}

if ($Mode -eq 'Start') {
    Assert-Deck
    $gpu=Read-Gpu
    if ($gpu.Inf -ne 'oem50.inf' -or $gpu.ProblemCode -ne 0 -or (Read-SelectedKernelHash $gpu) -ne $prototypeKernel) { throw 'The working prototype must be healthy at the start of this test.' }
    if (Test-Path -LiteralPath (Join-Path $trialDirectory 'reload-start.json')) { throw 'This one-time test was already started.' }
    $task=Get-ScheduledTask -TaskName $taskName
    if ($task.Principal.UserId -notin @('SYSTEM','S-1-5-18') -or $task.Actions.Execute -ne $powershell -or $task.Actions.Arguments -notlike ('*'+$Nonce+'*')) { throw 'The prepared elevated watchdog task does not match.' }
    if (-not (Read-Json (Join-Path $trialDirectory 'self-test.json')).Passed) { throw 'The recovery self-test has not passed.' }
    $stopAt=[datetime]::UtcNow.AddSeconds(30)
    while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running') {
        if ([datetime]::UtcNow -ge $stopAt) { throw 'The watchdog self-test has not exited.' }
        Start-Sleep -Seconds 1
    }
    Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Mode='Monitor'; RequestedUtc=[datetime]::UtcNow.ToString('o')})
    Start-ScheduledTask -TaskName $taskName
    $stopAt=[datetime]::UtcNow.AddSeconds(30)
    while ($true) {
        $status=Read-Json (Join-Path $trialDirectory 'watchdog-status.json')
        if ($status.Nonce -eq $Nonce -and $status.Status -eq 'WaitingForReload' -and ([datetime]::UtcNow-[datetime]::Parse($status.HeartbeatUtc).ToUniversalTime()).TotalSeconds -lt 10) { break }
        if ([datetime]::UtcNow -ge $stopAt) { throw 'The recovery watchdog did not arm; the driver was not switched.' }
        Start-Sleep -Seconds 1
    }
    & $applyScript -Mode SelectTrial -GuardNonce $Nonce
    exit $LASTEXITCODE
}

if ($Mode -eq 'Watch') {
    Assert-Deck
    $control=Read-Json (Join-Path $trialDirectory 'control.json')
    if ($control.Nonce -ne $Nonce) { throw 'Watchdog control belongs to another trial.' }
    if ($control.Mode -eq 'Idle') { exit 0 }
    if ($control.Mode -eq 'SelfTest') {
        $gpu=Read-Gpu
        $prototype=Read-Json (Join-Path $projectRoot 'private-driver\signed-package.json')
        $kernelHash=(Get-FileHash -LiteralPath (Join-Path $prototype.PackageDirectory 'B026204\amdkmdag.sys') -Algorithm SHA256).Hash
        $passed=$identity.User.Value -eq 'S-1-5-18' -and $gpu.Inf -eq 'oem50.inf' -and $gpu.ProblemCode -eq 0 -and $kernelHash -eq $prototypeKernel
        Write-Json (Join-Path $trialDirectory 'self-test.json') ([PSCustomObject]@{Nonce=$Nonce; Passed=$passed; Identity=$identity.User.Value; CheckedUtc=[datetime]::UtcNow.ToString('o'); Gpu=$gpu; PrototypeKernelSHA256=$kernelHash; DriverChangePerformed=$false; RestartRequested=$false})
        exit 0
    }
    if ($control.Mode -ne 'Monitor') { throw 'Unknown watchdog control mode.' }
    $decisionPath=Join-Path $trialDirectory 'decision.json'
    $startPath=Join-Path $trialDirectory 'reload-start.json'
    $waitingLimit=[datetime]::UtcNow.AddSeconds(120)
    Initialize-Native
    [void][GuardedDeckNative]::SetThreadExecutionState([uint32]2147483651)
    try {
        while (-not (Test-Path -LiteralPath $startPath)) {
            if ([datetime]::UtcNow -ge $waitingLimit) { Write-Status 'NotStarted'; Retire-Task; exit 0 }
            Write-Status 'WaitingForReload'
            Start-Sleep -Seconds 1
        }
        $start=Read-Json $startPath
        if ($start.Nonce -ne $Nonce -or $start.TimeoutSeconds -ne 180) { throw 'Invalid reload-start marker.' }
        $deadline=[datetime]::Parse($start.StartedUtc).ToUniversalTime().AddSeconds(180)
        while ([datetime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $decisionPath) {
                $decision=Read-Json $decisionPath
                if ($decision.Nonce -ne $Nonce -or $decision.Decision -ne 'Keep') { throw 'Unexpected premature recovery decision.' }
                Write-Status 'Kept'
                Retire-Task
                exit 0
            }
            Write-Status 'AwaitingReply' ([PSCustomObject]@{DeadlineUtc=$deadline.ToString('o')})
            Start-Sleep -Seconds 1
        }
        [void](New-ReloadDecision -Path $decisionPath -Token $Nonce -Decision Rollback -DeadlineUtc $deadline)
        $decision=Read-Json $decisionPath
        if ($decision.Nonce -ne $Nonce) { throw 'Recovery decision token mismatch.' }
        if ($decision.Decision -eq 'Keep') { Write-Status 'Kept'; Retire-Task; exit 0 }
        if ($decision.Decision -ne 'Rollback') { throw 'Invalid recovery decision.' }
        $currentGpu=Read-Gpu
        if ($currentGpu.Inf -eq 'oem50.inf' -and $currentGpu.ProblemCode -eq 0 -and (Read-SelectedKernelHash $currentGpu) -eq $prototypeKernel) {
            Write-Status 'PrototypeAlreadyRecovered' $currentGpu
            Retire-Task
            exit 0
        }
        Write-Status 'RestoringPrototype'
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$applyScript+'" -Mode RestorePrototype'
        $recovery=Start-Process -FilePath $powershell -WindowStyle Hidden -ArgumentList $arguments -PassThru
        if (-not $recovery.WaitForExit(45000)) { Write-Status 'RecoveryStillRunning' ([PSCustomObject]@{RecoveryProcessId=$recovery.Id}); exit 1 }
        $state=Read-Json (Join-Path $projectRoot 'config-trial-state.json')
        if ($recovery.ExitCode -ne 0 -or $state.Status -ne 'PrototypeSelectedNeedsRestart' -or $state.RestoredGpu.Inf -ne 'oem50.inf' -or $state.RestoredFiles.KernelSHA256 -ne $prototypeKernel) { throw 'Recovery did not verify the prototype selection; no automatic restart was requested.' }
        Write-Status 'PrototypeSelectedRestartRequested' $state.RestoredGpu
        Retire-Task
        & shutdown.exe /r /t 0
        if ($LASTEXITCODE -ne 0) { throw 'The prototype is selected, but Windows did not accept the restart request.' }
    } catch {
        Write-Status 'RecoveryFailed' ([PSCustomObject]@{Error=$_.Exception.Message})
        Retire-Task
        throw
    } finally { [void][GuardedDeckNative]::SetThreadExecutionState([uint32]2147483648) }
}
