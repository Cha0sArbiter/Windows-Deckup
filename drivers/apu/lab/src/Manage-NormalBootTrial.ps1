param(
    [ValidateSet('Prepare','Watch','Check','Keep','Recover','Audit','SelectCandidate','SelectPrototype')][string]$Mode='Check',
    [ValidatePattern('^$|^[a-fA-F0-9-]{36}$')][string]$Nonce=''
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$trialRoot=Join-Path $projectRoot 'normal-boot'
$nativeSource=Join-Path $PSScriptRoot 'DeferredDeckDriver.cs'
$taskName='SteamDeckDriverLab-NormalBootRecovery'
$instance='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE\4&2E94418C&0&0041'
$candidateHash='AE975BBB56282BE1471B9A91407F0155C087B619F99D2731D4E7989720522152'
$configHash='7EE54354831BBF267C590636FFFFD95FCA91FF5455578151FA657BD5F9162717'
$prototypeHash='E1B4DBFB807A59971BFC90E8139E35F96B4ADEDFD773695DBDCA5568B83D1ADF'
$candidateManifest=Join-Path $projectRoot 'private-config-install\signed-config-package.json'
$prototypeManifest=Join-Path $projectRoot 'private-driver\signed-package.json'
$powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Mode -in @('Prepare','Watch','Recover','SelectCandidate','SelectPrototype') -and -not $admin) { throw 'Run this mode with Windows administrator rights.' }

function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Write-Json([string]$Path,$Value) {
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $previous=$temporary+'.previous'
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    try {
        for ($attempt=0; $attempt -lt 10; $attempt++) {
            try {
                if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,$previous) } else { [IO.File]::Move($temporary,$Path) }
                return
            } catch [IO.IOException] { if ($attempt -eq 9) { throw }; Start-Sleep -Milliseconds 25 }
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($previous)) { [IO.File]::Delete($previous) }
    }
}
function New-BootDecision {
    param([string]$Path,[string]$Token,[ValidateSet('Keep','Rollback')][string]$Decision,[datetime]$DeadlineUtc,[datetime]$NowUtc=[datetime]::UtcNow)
    if ($Decision -eq 'Keep' -and $NowUtc -ge $DeadlineUtc) { throw 'The normal-boot acknowledgment window expired.' }
    if ($Decision -eq 'Rollback' -and $NowUtc -lt $DeadlineUtc) { throw 'Recovery cannot begin before the deadline.' }
    if ([IO.File]::Exists($Path)) {
        if ((Read-Json $Path).Nonce -ne $Token) { throw 'A different trial owns the decision.' }
        return $false
    }
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,(([PSCustomObject]@{Nonce=$Token; Decision=$Decision; DecidedUtc=$NowUtc.ToUniversalTime().ToString('o')}) | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$Path)
        return $true
    } catch [IO.IOException] { if (-not [IO.File]::Exists($Path)) { throw }; return $false
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Initialize-Native { if (-not ('DeferredDeckDriver' -as [type])) { Add-Type -Path $nativeSource } }
function Read-CodeIntegrity {
    Initialize-Native
    $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer,8); $length=0
        if ([DeferredDeckDriver]::NtQuerySystemInformation(103,$buffer,8,[ref]$length) -ne 0) { throw 'Could not query live Code Integrity.' }
        $options=[Runtime.InteropServices.Marshal]::ReadInt32($buffer,4)
        [PSCustomObject]@{Options=$options; TestSigningActive=(($options -band 2) -ne 0)}
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
}
function Read-Boot { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss'Z'") }
function Read-Gpu {
    $values=@{}
    Get-PnpDeviceProperty -InstanceId $instance -KeyName 'DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_Service' | ForEach-Object { $values[$_.KeyName]=$_.Data }
    foreach ($key in @('DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_Service')) { if ($null -eq $values[$key]) { throw "Missing GPU property $key" } }
    [PSCustomObject]@{InstanceId=$instance; ProblemCode=[int]$values['DEVPKEY_Device_ProblemCode']; Inf=[string]$values['DEVPKEY_Device_DriverInfPath']; Version=[string]$values['DEVPKEY_Device_DriverVersion']; Service=[string]$values['DEVPKEY_Device_Service']}
}
function Read-SelectedFiles($Gpu) {
    $image=[string](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$Gpu.Service) -Name ImagePath).ImagePath
    $path=[Environment]::ExpandEnvironmentVariables($image).Trim('"')
    if ($path.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)) { $path=Join-Path $env:SystemRoot $path.Substring(12) }
    if ($path.StartsWith('\??\')) { $path=$path.Substring(4) }
    $path=[IO.Path]::GetFullPath($path)
    $storeRoot=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository')).TrimEnd('\')+'\'
    if (-not $path.StartsWith($storeRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -ne 'amdkmdag.sys') { throw 'Unexpected selected GPU kernel path.' }
    $config=Join-Path (Split-Path -Parent $path) 'amdgcf.dat'
    $driverKey=[string](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Enum\'+$instance) -Name Driver).Driver
    $inf=[string](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\Class\'+$driverKey) -Name InfPath).InfPath
    [PSCustomObject]@{KernelPath=$path; KernelSHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; ConfigurationPath=$config; ConfigurationSHA256=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash; RegisteredInf=$inf}
}
function Read-BcdTest {
    $lines=@(& bcdedit.exe /enum '{current}' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read current boot entry.' }
    $matches=@($lines | Where-Object { [string]$_ -match '^\s*testsigning\s+' })
    if ($matches.Count -gt 1) { throw 'Ambiguous Test Mode boot setting.' }
    if ($matches.Count) { return (([string]$matches[0] -split '\s+')[-1]) }
    'Absent'
}
function Set-BcdTest([ValidateSet('ON','OFF')][string]$Value) {
    & bcdedit.exe /set '{current}' TESTSIGNING $Value | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not set TESTSIGNING $Value." }
    $expected=if ($Value -eq 'ON') {'Yes'} else {'No'}
    if ((Read-BcdTest) -ne $expected) { throw 'Boot setting verification failed.' }
}
function Assert-FileSet([string]$Root,$Files) {
    $root=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    foreach ($file in $Files) {
        $path=[IO.Path]::GetFullPath((Join-Path $root $file.Path))
        if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escapes its package.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw "Package mismatch: $($file.Path)" }
    }
    @($Files).Count
}
function Assert-Package($Manifest) { [void](Assert-FileSet $Manifest.PackageDirectory $Manifest.Files) }
function Assert-StagedPackage($Manifest,[string]$PublishedInf) {
    $inf=[DeferredDeckDriver]::ResolveStagedInf((Join-Path $env:SystemRoot ('INF\'+$PublishedInf)))
    if ([IO.Path]::GetFileName($inf) -ne $Manifest.MainInf) { throw 'The published INF resolves to a different staged package.' }
    $catalog=[IO.Path]::ChangeExtension($Manifest.MainInf,'.cat')
    $files=@($Manifest.Files | Where-Object { $_.Path -eq $Manifest.MainInf -or $_.Path -eq $catalog -or $_.Path.StartsWith('B026204\',[StringComparison]::OrdinalIgnoreCase) })
    if ($files.Count -ne 132) { throw 'Unexpected exact-build main-package layout.' }
    $count=Assert-FileSet (Split-Path -Parent $inf) $files
    [PSCustomObject]@{PublishedInf=$PublishedInf; DriverStoreInf=$inf; VerifiedFiles=$count; VerifiedUtc=[datetime]::UtcNow.ToString('o')}
}
function Assert-SharedSystemFiles($Candidate,$Prototype) {
    $candidateFiles=@{}; $prototypeFiles=@{}
    foreach ($file in $Candidate.Files) { $candidateFiles[$file.Path]=$file.SHA256 }
    foreach ($file in $Prototype.Files) { $prototypeFiles[$file.Path]=$file.SHA256 }
    $section=''; $records=@()
    foreach ($raw in Get-Content -LiteralPath (Join-Path $Candidate.PackageDirectory $Candidate.MainInf)) {
        $line=($raw -split ';',2)[0].Trim()
        if (-not $line) { continue }
        if ($line -match '^\[(.+)\]$') { $section=$matches[1]; continue }
        if ($section -notin @('DS.System32','DS.SysWow64')) { continue }
        $columns=@($line -split ','); $destination=$columns[0].Trim(); $source=$destination
        if ($columns.Count -gt 1 -and $columns[1].Trim()) { $source=$columns[1].Trim() }
        if ([IO.Path]::GetFileName($source) -ne $source -or [IO.Path]::GetFileName($destination) -ne $destination) { throw 'Unexpected shared-copy filename.' }
        $relative='B026204\'+$source; $expected=$candidateFiles[$relative]
        if (-not $expected -or $prototypeFiles[$relative] -ne $expected) { throw 'A shared component differs between the two driver variants.' }
        $directory=if ($section -eq 'DS.System32') { 'System32' } else { 'SysWOW64' }
        $path=Join-Path (Join-Path $env:SystemRoot $directory) $destination
        $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne $expected) { throw "Shared system component missing or changed: $path" }
        $records += [PSCustomObject]@{Path=$path; SHA256=$actual; Source=$relative}
    }
    if ($records.Count -ne 56) { throw 'Unexpected shared-system file list.' }
    [PSCustomObject]@{VerifiedFiles=$records.Count; Files=$records; VerifiedUtc=[datetime]::UtcNow.ToString('o')}
}
function Assert-Plan($Plan) {
    if ($Plan.Nonce -ne $Nonce -or $Plan.TaskName -ne $taskName -or $Plan.TimeoutSeconds -ne 180) { throw 'Unexpected normal-mode recovery plan.' }
    foreach ($pair in @(@($PSCommandPath,$Plan.WorkerSHA256),@($nativeSource,$Plan.NativeSHA256),@($candidateManifest,$Plan.CandidateManifestSHA256),@($prototypeManifest,$Plan.PrototypeManifestSHA256))) {
        if ((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ne $pair[1]) { throw 'A prepared recovery component changed.' }
    }
}
function Write-Status([string]$Status,$Details=$null) {
    Write-Json (Join-Path $trialDirectory 'status.json') ([PSCustomObject]@{Nonce=$Nonce; Status=$Status; UpdatedUtc=[datetime]::UtcNow.ToString('o'); Identity=$identity.User.Value; ProcessId=$PID; Details=$Details})
}
function Retire-Task {
    $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task -and $task.Actions.Arguments -like ('*'+$Nonce+'*')) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
}
function Read-Snapshot {
    $gpu=Read-Gpu
    [PSCustomObject]@{CapturedUtc=[datetime]::UtcNow.ToString('o'); BootUtc=(Read-Boot); Gpu=$gpu; CodeIntegrity=(Read-CodeIntegrity); SelectedFiles=(Read-SelectedFiles $gpu)}
}
function Assert-NormalSnapshot($Snapshot,$Plan) {
    if ($Snapshot.BootUtc -eq $Plan.BootBeforeUtc) { throw 'The normal-mode boot has not occurred.' }
    if ($Snapshot.CodeIntegrity.TestSigningActive) { throw 'Test Mode is still active in the running kernel.' }
    if ($Snapshot.Gpu.Inf -ne 'oem56.inf' -or $Snapshot.Gpu.Version -ne '32.0.21043.21001' -or $Snapshot.Gpu.ProblemCode -ne 0 -or $Snapshot.SelectedFiles.RegisteredInf -ne 'oem56.inf') { throw 'The configuration-only GPU is not selected and healthy.' }
    if ($Snapshot.SelectedFiles.KernelSHA256 -ne $candidateHash -or $Snapshot.SelectedFiles.ConfigurationSHA256 -ne $configHash) { throw 'Normal-mode candidate file hashes differ.' }
}
function Invoke-BoundedPowerShell([string]$Arguments,[string]$LogPrefix,[int]$TimeoutMilliseconds=45000) {
    # Retain the actual process handle. Start-Process's detached Process wrapper
    # can expose a null ExitCode after exit in Windows PowerShell 5.
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$powershell; $start.Arguments=$Arguments
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
    $output=$null; $errorOutput=$null
    try {
        if (-not $process.Start()) { throw 'Could not launch the selection child.' }
        [void]$process.Handle
        $output=$process.StandardOutput.ReadToEndAsync()
        $errorOutput=$process.StandardError.ReadToEndAsync()
        Write-Json ($LogPrefix+'-process.json') ([PSCustomObject]@{Nonce=$Nonce; ProcessId=$process.Id; StartedUtc=[datetime]::UtcNow.ToString('o'); TimeoutMilliseconds=$TimeoutMilliseconds})
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            $process.Kill(); [void]$process.WaitForExit(5000)
            throw 'Selection child timed out and was stopped.'
        }
        $code=$process.ExitCode
        if ($null -eq $code) { throw 'The selection child exit status is unavailable.' }
        [PSCustomObject]@{ExitCode=[int]$code; ProcessId=$process.Id}
    } finally {
        if ($null -ne $output -and $output.IsCompleted -and -not $output.IsFaulted) { [IO.File]::WriteAllText(($LogPrefix+'.stdout.log'),$output.GetAwaiter().GetResult()) }
        if ($null -ne $errorOutput -and $errorOutput.IsCompleted -and -not $errorOutput.IsFaulted) { [IO.File]::WriteAllText(($LogPrefix+'.stderr.log'),$errorOutput.GetAwaiter().GetResult()) }
        $process.Dispose()
    }
}
function Invoke-DeferredSelection([ValidateSet('Candidate','Prototype')][string]$Target) {
    $resultPath=Join-Path $trialDirectory ('selection-'+$Target+'.json')
    if (Test-Path -LiteralPath $resultPath) { throw 'A selection result already exists for this trial phase.' }
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode Select'+$Target+' -Nonce '+$Nonce
    $child=Invoke-BoundedPowerShell -Arguments $arguments -LogPrefix (Join-Path $trialDirectory ('selection-'+$Target))
    if ($child.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $resultPath)) { throw "Deferred $Target selection failed (exit $($child.ExitCode)); inspect its progress and stderr logs." }
    $result=Read-Json $resultPath
    if ($result.Nonce -ne $Nonce -or $result.Target -ne $Target -or -not $result.Selection.RestartRequired -or -not $result.Selection.FileCopySuppressed) { throw 'Unexpected deferred-selection result.' }
    $result.Selection
}
function Invoke-Recovery([string]$Reason) {
    Write-Status 'Recovering' $Reason
    Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Phase='Recovering'})
    Assert-Plan $plan
    $prototype=Read-Json $prototypeManifest
    Assert-Package $prototype
    # Enable the next boot's Test Mode BEFORE selecting the test-signed fallback.
    Set-BcdTest ON
    $selection=Invoke-DeferredSelection Prototype
    $gpu=Read-Gpu; $files=Read-SelectedFiles $gpu
    if ($files.RegisteredInf -ne 'oem50.inf' -or $files.KernelSHA256 -ne $prototypeHash -or (Read-BcdTest) -ne 'Yes') { throw 'Recovery selection or boot-setting verification failed.' }
    Write-Json (Join-Path $trialDirectory 'recovery-selection.json') ([PSCustomObject]@{Reason=$Reason; Selection=$selection; Gpu=$gpu; SelectedFiles=$files; BcdTestSigning='Yes'; SelectedUtc=[datetime]::UtcNow.ToString('o')})
    Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Phase='RecoveryPendingRestart'; RecoveryBootBeforeUtc=(Read-Boot)})
    Write-Status 'PrototypeSelectedTestModeEnabledRestartRequested'
    & shutdown.exe /r /t 0
    if ($LASTEXITCODE -ne 0) { throw 'Recovery restart request failed.' }
}

Initialize-Native
if ($Mode -eq 'Audit') {
    $candidate=Read-Json $candidateManifest; $prototype=Read-Json $prototypeManifest
    Assert-Package $candidate; Assert-Package $prototype
    [PSCustomObject]@{Snapshot=(Read-Snapshot); CandidateStaged=(Assert-StagedPackage $candidate 'oem56.inf'); PrototypeStaged=(Assert-StagedPackage $prototype 'oem50.inf'); SharedSystem=(Assert-SharedSystemFiles $candidate $prototype)} | ConvertTo-Json -Depth 8
    exit 0
}
if ($Mode -eq 'Prepare') {
    # A delayed UAC launch and a manual launcher must not prepare two trials.
    # Keep this named mutex alive until the preparation process exits.
    $preparationMutex=[Threading.Mutex]::new($false,'Global\SteamDeckDriverLabNormalBootPrepare')
    $ownsPreparation=$false
    try { $ownsPreparation=$preparationMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsPreparation=$true }
    if (-not $ownsPreparation) { throw 'Another normal-mode preparation helper is already running.' }
    New-Item -ItemType Directory -Path $trialRoot -Force | Out-Null
    Start-Transcript -LiteralPath (Join-Path $trialRoot ('prepare-'+[guid]::NewGuid().ToString('N')+'.log')) | Out-Null
    $computer=Get-CimInstance Win32_ComputerSystem
    if ($computer.Manufacturer -ne 'Valve' -or $computer.Model -ne 'Jupiter') { throw 'This trial is restricted to the LCD Deck.' }
    $before=Read-Snapshot
    if (-not $before.CodeIntegrity.TestSigningActive -or $before.Gpu.Inf -ne 'oem50.inf' -or $before.Gpu.ProblemCode -ne 0 -or $before.SelectedFiles.KernelSHA256 -ne $prototypeHash) { throw 'The working Test Mode prototype must be healthy before preparation.' }
    $previousTask=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($previousTask) {
        # Retire only the completed wrapper-error trial while the verified
        # prototype remains selected. Never overwrite a working/pending guard.
        $previousActive=Read-Json (Join-Path $trialRoot 'active.json')
        $previousStatus=Read-Json (Join-Path $previousActive.Directory 'status.json')
        $previousControl=Read-Json (Join-Path $previousActive.Directory 'control.json')
        if ($previousTask.State -eq 'Running' -or $previousStatus.Nonce -ne $previousActive.Nonce -or $previousStatus.Status -ne 'RecoveryWatcherError' -or $previousControl.Phase -ne 'Recovering' -or $previousTask.Actions.Arguments -notlike ('*'+$previousActive.Nonce+'*') -or $before.SelectedFiles.RegisteredInf -ne 'oem50.inf' -or (Read-BcdTest) -ne 'Yes') { throw 'A normal-boot recovery task already exists; inspect it first.' }
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Json (Join-Path $previousActive.Directory 'retired-wrapper-error.json') ([PSCustomObject]@{Nonce=$previousActive.Nonce; Status='RetiredPrototypeVerified'; Snapshot=$before; BcdTestSigning='Yes'; CompletedUtc=[datetime]::UtcNow.ToString('o')})
        Write-Json (Join-Path $previousActive.Directory 'status.json') ([PSCustomObject]@{Nonce=$previousActive.Nonce; Status='RetiredPrototypeVerified'; UpdatedUtc=[datetime]::UtcNow.ToString('o')})
    }
    $candidate=Read-Json $candidateManifest; $prototype=Read-Json $prototypeManifest
    if ($candidate.KernelModified -or $candidate.KernelSHA256 -ne $candidateHash -or $candidate.ConfigurationSHA256 -ne $configHash -or $prototype.KernelSHA256 -ne $prototypeHash) { throw 'Unexpected candidate/fallback metadata.' }
    Assert-Package $candidate; Assert-Package $prototype
    $candidateStaged=Assert-StagedPackage $candidate 'oem56.inf'
    $prototypeStaged=Assert-StagedPackage $prototype 'oem50.inf'
    $sharedFiles=Assert-SharedSystemFiles $candidate $prototype
    foreach ($pair in @(@('oem56.inf',(Join-Path $candidate.PackageDirectory $candidate.MainInf)),@('oem50.inf',(Join-Path $prototype.PackageDirectory $prototype.MainInf)))) {
        if ((Get-FileHash -LiteralPath (Join-Path $env:SystemRoot ('INF\'+$pair[0])) -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash) { throw 'Expected candidate/fallback INF is not staged.' }
        [DeferredDeckDriver]::Inspect((Join-Path $env:SystemRoot ('INF\'+$pair[0]))) | Out-Null
    }
    $Nonce=[guid]::NewGuid().ToString()
    $trialDirectory=Join-Path $trialRoot $Nonce
    New-Item -ItemType Directory -Path $trialDirectory -Force | Out-Null
    Write-Json (Join-Path $trialDirectory 'staged-file-verification.json') ([PSCustomObject]@{Candidate=$candidateStaged; Prototype=$prototypeStaged; SharedSystem=$sharedFiles})
    $taskRoot=Split-Path -Parent (Split-Path -Parent $projectRoot)
    $signTool=Join-Path $taskRoot 'work\driver-audit\tools\sdk-buildtools\bin\10.0.26100.0\x64\signtool.exe'
    $signatureResults=@()
    foreach ($file in $candidate.Files | Where-Object { $_.Path -like '*.sys' }) {
        $path=Join-Path $candidate.PackageDirectory $file.Path
        # SignTool /a can report a rejected local catalog before finding the valid
        # Microsoft catalog. Windows PowerShell 5 treats stderr as ErrorRecords;
        # decide using the verifier's final exit code rather than an early stderr.
        $previousPreference=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            $text=@(& $signTool verify /kp /a /hash SHA256 $path 2>&1); $result=$LASTEXITCODE
        } finally { $ErrorActionPreference=$previousPreference }
        $signatureResults += [PSCustomObject]@{Path=$path; ExitCode=$result; Output=($text -join "`n")}
        if ($result -ne 0) { throw "Microsoft kernel-policy verification failed: $($file.Path)" }
    }
    Write-Json (Join-Path $trialDirectory 'kernel-signature-verification.json') $signatureResults
    & bcdedit.exe /export (Join-Path $trialDirectory 'bcd-before.bin') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not back up boot configuration.' }
    & bcdedit.exe /enum '{current}' | Set-Content -LiteralPath (Join-Path $trialDirectory 'bcd-before.txt')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'config-trial-state.json') -Destination (Join-Path $trialDirectory 'previous-config-trial-state.json')
    $plan=[PSCustomObject]@{Nonce=$Nonce; TaskName=$taskName; TimeoutSeconds=180; PreparedUtc=[datetime]::UtcNow.ToString('o'); BootBeforeUtc=$before.BootUtc; Before=$before; WorkerSHA256=(Get-FileHash -LiteralPath $PSCommandPath).Hash; NativeSHA256=(Get-FileHash -LiteralPath $nativeSource).Hash; CandidateManifestSHA256=(Get-FileHash -LiteralPath $candidateManifest).Hash; PrototypeManifestSHA256=(Get-FileHash -LiteralPath $prototypeManifest).Hash; CandidateInf='oem56.inf'; PrototypeInf='oem50.inf'; CandidateKernelSHA256=$candidateHash; CandidateConfigurationSHA256=$configHash; PrototypeKernelSHA256=$prototypeHash}
    Write-Json (Join-Path $trialDirectory 'plan.json') $plan
    Write-Json (Join-Path $trialRoot 'active.json') ([PSCustomObject]@{Nonce=$Nonce; Directory=$trialDirectory; TaskName=$taskName})
    Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Phase='SelfTest'})
    $registered=$false; $armed=$false
    try {
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode Watch -Nonce '+$Nonce
        $action=New-ScheduledTaskAction -Execute $powershell -Argument $arguments
        $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Trigger (New-ScheduledTaskTrigger -AtStartup) -Description 'One normal-mode Deck driver boot; restores Test Mode and the verified prototype after 180 seconds without confirmation.' | Out-Null
        $registered=$true
        Start-ScheduledTask -TaskName $taskName
        $stopAt=[datetime]::UtcNow.AddSeconds(45)
        $selfTestPath=Join-Path $trialDirectory 'self-test.json'
        while (-not (Test-Path -LiteralPath $selfTestPath)) { if ([datetime]::UtcNow -ge $stopAt) { throw 'SYSTEM recovery self-test timed out.' }; Start-Sleep -Seconds 1 }
        $test=Read-Json $selfTestPath
        if (-not $test.Passed -or $test.Identity -ne 'S-1-5-18' -or $test.Nonce -ne $Nonce) { throw 'SYSTEM recovery self-test failed.' }
        while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running') { if ([datetime]::UtcNow -ge $stopAt) { throw 'SYSTEM self-test did not exit.' }; Start-Sleep -Milliseconds 250 }
        Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Phase='Preparing'; DeadlineUtc=[datetime]::UtcNow.AddSeconds(180).ToString('o')})
        Start-ScheduledTask -TaskName $taskName
        $stopAt=[datetime]::UtcNow.AddSeconds(30)
        while ($true) {
            $statusPath=Join-Path $trialDirectory 'status.json'
            if ((Test-Path -LiteralPath $statusPath) -and (Read-Json $statusPath).Status -eq 'GuardingPreparation') { break }
            if ([datetime]::UtcNow -ge $stopAt) { throw 'SYSTEM preparation guard did not start.' }; Start-Sleep -Milliseconds 250
        }
        $armed=$true
        Write-Status 'SelectingCandidateForReboot'
        $selection=Invoke-DeferredSelection Candidate
        $gpu=Read-Gpu; $files=Read-SelectedFiles $gpu
        if ($files.RegisteredInf -ne 'oem56.inf' -or $files.KernelSHA256 -ne $candidateHash -or $files.ConfigurationSHA256 -ne $configHash) { throw 'Deferred candidate selection did not update the expected registered INF/files.' }
        # This changes NEXT BOOT only; the currently running kernel remains in Test Mode.
        Set-BcdTest OFF
        Write-Json (Join-Path $trialDirectory 'prepared.json') ([PSCustomObject]@{Nonce=$Nonce; Status='ReadyForNormalModeRestart'; SelectedUtc=[datetime]::UtcNow.ToString('o'); Selection=$selection; Gpu=$gpu; SelectedFiles=$files; BcdTestSigning='No'; RunningCodeIntegrity=(Read-CodeIntegrity); RebootInitiated=$false})
        Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Phase='ReadyForReboot'})
        Write-Status 'ReadyForNormalModeRestart'
        Write-Output 'Ready: configuration-only driver selected for reboot, next boot TESTSIGNING OFF, SYSTEM startup recovery armed. Restart Windows and report whether the display works.'
    } catch {
        Write-Json (Join-Path $trialDirectory 'preparation-error.json') ([PSCustomObject]@{Error=$_.Exception.Message; Armed=$armed; Utc=[datetime]::UtcNow.ToString('o')})
        if ($armed) { Write-Json (Join-Path $trialDirectory 'control.json') ([PSCustomObject]@{Nonce=$Nonce; Phase='RecoverNow'}) } elseif ($registered) { Stop-ScheduledTask -TaskName $taskName; Retire-Task }
        throw
    }
    exit 0
}

if (-not $Nonce) { $Nonce=[string](Read-Json (Join-Path $trialRoot 'active.json')).Nonce }
$token=[guid]::Empty
if (-not [guid]::TryParse($Nonce,[ref]$token)) { throw 'Invalid normal-boot trial identifier.' }
$trialDirectory=Join-Path $trialRoot $Nonce
$plan=Read-Json (Join-Path $trialDirectory 'plan.json')
Assert-Plan $plan
if ($Mode -in @('SelectCandidate','SelectPrototype')) {
    $target=if ($Mode -eq 'SelectCandidate') { 'Candidate' } else { 'Prototype' }
    $control=Read-Json (Join-Path $trialDirectory 'control.json')
    if ($control.Nonce -ne $Nonce) { throw 'Wrong selection control owner.' }
    if ($target -eq 'Candidate') {
        if ($control.Phase -ne 'Preparing' -or [datetime]::UtcNow -ge [datetime]::Parse($control.DeadlineUtc).ToUniversalTime() -or -not (Read-CodeIntegrity).TestSigningActive) { throw 'Candidate selection is outside the guarded Test Mode preparation window.' }
    } elseif ($control.Phase -ne 'Recovering' -or (Read-BcdTest) -ne 'Yes') { throw 'Recovery selection requires next-boot Test Mode already enabled.' }
    $candidate=Read-Json $candidateManifest; $prototype=Read-Json $prototypeManifest
    $manifest=if ($target -eq 'Candidate') { $candidate } else { $prototype }
    $inf=if ($target -eq 'Candidate') { 'oem56.inf' } else { 'oem50.inf' }
    Assert-Package $manifest
    $staged=Assert-StagedPackage $manifest $inf
    $shared=Assert-SharedSystemFiles $candidate $prototype
    $progressPath=Join-Path $trialDirectory ('selection-'+$target+'-progress.json')
    $callback=[Action[string]]{param($step) Write-Json $progressPath ([PSCustomObject]@{Nonce=$Nonce; Target=$target; Step=$step; ProcessId=$PID; UpdatedUtc=[datetime]::UtcNow.ToString('o')})}
    $selection=[DeferredDeckDriver]::SelectForReboot((Join-Path $env:SystemRoot ('INF\'+$inf)),$callback)
    Write-Json (Join-Path $trialDirectory ('selection-'+$target+'.json')) ([PSCustomObject]@{Nonce=$Nonce; Target=$target; Selection=$selection; StagedFiles=$staged; SharedSystemFiles=$shared.VerifiedFiles; CompletedUtc=[datetime]::UtcNow.ToString('o')})
    exit 0
}
if ($Mode -in @('Check','Keep')) {
    $snapshot=Read-Snapshot
    Assert-NormalSnapshot $snapshot $plan
    Write-Json (Join-Path $trialDirectory 'normal-boot-verification.json') $snapshot
    if ($Mode -eq 'Keep') {
        $start=Read-Json (Join-Path $trialDirectory 'boot-start.json')
        if ($start.Nonce -ne $Nonce -or $start.BootUtc -ne $snapshot.BootUtc) { throw 'The normal-boot guard has not opened this boot window.' }
        [void](New-BootDecision -Path (Join-Path $trialDirectory 'decision.json') -Token $Nonce -Decision Keep -DeadlineUtc ([datetime]::Parse($start.DeadlineUtc).ToUniversalTime()))
        if ((Read-Json (Join-Path $trialDirectory 'decision.json')).Decision -ne 'Keep') { throw 'Recovery has already committed.' }
        Write-Output 'Normal-mode boot verified and acknowledged. The SYSTEM watcher will remove its recovery task.'
    } else { $snapshot | ConvertTo-Json -Depth 6 }
    exit 0
}
if ($Mode -eq 'Recover') { Invoke-Recovery 'Manual recovery requested'; exit 0 }

# The scheduled SYSTEM watcher survives UI loss and runs at the next startup.
try {
    if ($identity.User.Value -ne 'S-1-5-18') { throw 'Watch must run under the prepared SYSTEM task.' }
    $control=Read-Json (Join-Path $trialDirectory 'control.json')
    if ($control.Nonce -ne $Nonce) { throw 'Wrong trial control file.' }
    if ($control.Phase -eq 'SelfTest') {
        $snapshot=Read-Snapshot
        if ($snapshot.BootUtc -ne $plan.BootBeforeUtc -or -not $snapshot.CodeIntegrity.TestSigningActive -or $snapshot.Gpu.ProblemCode -ne 0 -or $snapshot.SelectedFiles.KernelSHA256 -ne $prototypeHash) { throw 'SYSTEM self-test baseline differs.' }
        Write-Json (Join-Path $trialDirectory 'self-test.json') ([PSCustomObject]@{Nonce=$Nonce; Passed=$true; Identity=$identity.User.Value; Snapshot=$snapshot; CompletedUtc=[datetime]::UtcNow.ToString('o')})
        Write-Status 'SelfTestPassed'
        exit 0
    }
    [void][DeferredDeckDriver]::SetThreadExecutionState([uint32]2147483651)
    $boot=Read-Boot
    if ($boot -eq $plan.BootBeforeUtc) {
        if ($control.Phase -eq 'ReadyForReboot') { Write-Status 'ReadyForNormalModeRestart'; exit 0 }
        if ($control.Phase -notin @('Preparing','RecoverNow')) { throw 'Unexpected preparation guard phase.' }
        Write-Status 'GuardingPreparation'
        while ($true) {
            $control=Read-Json (Join-Path $trialDirectory 'control.json')
            if ($control.Phase -eq 'ReadyForReboot') { Write-Status 'ReadyForNormalModeRestart'; exit 0 }
            if ($control.Phase -eq 'RecoverNow' -or [datetime]::UtcNow -ge [datetime]::Parse($control.DeadlineUtc).ToUniversalTime()) { Invoke-Recovery 'Preparation failed or timed out'; exit 0 }
            Start-Sleep -Seconds 1
        }
    }
    if ($control.Phase -eq 'RecoveryPendingRestart') {
        if ($boot -eq $control.RecoveryBootBeforeUtc) { Write-Status 'RecoveryRestartStillRequired'; exit 0 }
        # The startup task can run before PnP has finished initializing the GPU.
        $stopAt=[datetime]::UtcNow.AddSeconds(45)
        do {
            $snapshot=$null
            try {
                $snapshot=Read-Snapshot
                if ($snapshot.CodeIntegrity.TestSigningActive -and $snapshot.Gpu.ProblemCode -eq 0 -and $snapshot.Gpu.Inf -eq 'oem50.inf' -and $snapshot.SelectedFiles.RegisteredInf -eq 'oem50.inf' -and $snapshot.SelectedFiles.KernelSHA256 -eq $prototypeHash) { break }
            } catch { Write-Status 'WaitingForRecoveryGpu' $_.Exception.Message }
            Start-Sleep -Seconds 1
        } while ([datetime]::UtcNow -lt $stopAt)
        Write-Json (Join-Path $trialDirectory 'recovery-boot.json') $snapshot
        if ($null -eq $snapshot -or -not $snapshot.CodeIntegrity.TestSigningActive -or $snapshot.Gpu.ProblemCode -ne 0 -or $snapshot.Gpu.Inf -ne 'oem50.inf' -or $snapshot.SelectedFiles.RegisteredInf -ne 'oem50.inf' -or $snapshot.SelectedFiles.KernelSHA256 -ne $prototypeHash) { Write-Status 'RecoveryBootNeedsInspection' $snapshot; Retire-Task; exit 1 }
        Write-Status 'PrototypeRecoveryVerified' $snapshot
        Retire-Task
        exit 0
    }
    if ($control.Phase -ne 'ReadyForReboot') { throw 'The next-boot trial was not fully prepared.' }
    $startPath=Join-Path $trialDirectory 'boot-start.json'
    if (Test-Path -LiteralPath $startPath) {
        $start=Read-Json $startPath
        if ($start.Nonce -ne $Nonce -or $start.BootUtc -ne $boot) { Invoke-Recovery 'Unexpected extra boot during unconfirmed trial'; exit 0 }
    } else {
        $start=[PSCustomObject]@{Nonce=$Nonce; BootUtc=$boot; StartedUtc=[datetime]::UtcNow.ToString('o'); DeadlineUtc=[datetime]::UtcNow.AddSeconds(180).ToString('o')}
        Write-Json $startPath $start
    }
    Write-Status 'WaitingForNormalBootConfirmation' $start
    try { Write-Json (Join-Path $trialDirectory 'startup-snapshot.json') (Read-Snapshot) } catch { Write-Json (Join-Path $trialDirectory 'startup-snapshot-error.json') ([PSCustomObject]@{Error=$_.Exception.Message}) }
    $deadline=[datetime]::Parse($start.DeadlineUtc).ToUniversalTime()
    $decisionPath=Join-Path $trialDirectory 'decision.json'
    while ($true) {
        if (Test-Path -LiteralPath $decisionPath) {
            $decision=Read-Json $decisionPath
            if ($decision.Nonce -ne $Nonce) { throw 'Wrong normal-boot decision.' }
            if ($decision.Decision -eq 'Keep') { Write-Status 'NormalModeCandidateKept'; Retire-Task; exit 0 }
            if ($decision.Decision -eq 'Rollback') { Invoke-Recovery 'No normal-boot display confirmation within 180 seconds'; exit 0 }
            throw 'Invalid normal-boot decision.'
        }
        if ([datetime]::UtcNow -ge $deadline) { [void](New-BootDecision -Path $decisionPath -Token $Nonce -Decision Rollback -DeadlineUtc $deadline); continue }
        Start-Sleep -Seconds 1
    }
} catch {
    Write-Status 'RecoveryWatcherError' ([PSCustomObject]@{Error=$_.Exception.Message})
    exit 1
} finally { [void][DeferredDeckDriver]::SetThreadExecutionState([uint32]2147483648) }
