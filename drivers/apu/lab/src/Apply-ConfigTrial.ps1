param(
    [ValidateSet('SelectTrial','RestorePrototype','Check')][string]$Mode='SelectTrial',
    [ValidatePattern('^$|^[a-fA-F0-9-]{36}$')][string]$GuardNonce=''
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$taskRoot=Split-Path -Parent (Split-Path -Parent $projectRoot)
$trialRoot=Join-Path $projectRoot 'private-config-install'
$statePath=Join-Path $projectRoot 'config-trial-state.json'
$signed=Get-Content -LiteralPath (Join-Path $trialRoot 'signed-config-package.json') -Raw | ConvertFrom-Json
$prototype=Get-Content -LiteralPath (Join-Path $projectRoot 'private-driver\signed-package.json') -Raw | ConvertFrom-Json
$expectedHardware='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE'
$expectedVersion='32.0.21043.21001'
$expectedKernel='ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152'
$expectedConfig='7ee54354831bbf267c590636ffffd95fca91ff5455578151fa657bd5f9162717'
$prototypeKernel='E1B4DBFB807A59971BFC90E8139E35F96B4ADEDFD773695DBDCA5568B83D1ADF'
$signTool=Join-Path $taskRoot 'work\driver-audit\tools\sdk-buildtools\bin\10.0.26100.0\x64\signtool.exe'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if ($Mode -ne 'Check' -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run the configuration trial helper as administrator.' }
if ($signed.HardwareId -ne $expectedHardware -or $signed.DriverVersion -ne $expectedVersion -or $signed.KernelModified -or $signed.KernelSHA256 -ne $expectedKernel -or $signed.ConfigurationSHA256 -ne $expectedConfig) { throw 'Unexpected configuration-only package metadata.' }
if ($signed.MainInf -ne 'decklcd-config.inf' -or $signed.ExtensionInf -ne 'decklcd-config-extension.inf') { throw 'Unexpected trial INF names.' }
if ($prototype.HardwareId -ne $expectedHardware -or $prototype.DriverVersion -ne $expectedVersion -or $prototype.KernelSHA256 -ne $prototypeKernel) { throw 'Unexpected prototype fallback metadata.' }
if ([IO.Path]::GetFullPath($signed.PackageDirectory) -ne (Join-Path $trialRoot 'WT6A_INF')) { throw 'Unexpected trial package path.' }
if ([IO.Path]::GetFullPath($prototype.PackageDirectory) -ne (Join-Path $projectRoot 'private-driver\WT6A_INF')) { throw 'Unexpected fallback package path.' }
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'logs') -Force | Out-Null
Start-Transcript -LiteralPath (Join-Path $projectRoot ('logs\config-'+$Mode.ToLowerInvariant()+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')) -Force | Out-Null
$state=if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
$bindingAttempted=$false

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DeckConfigNative {
    [DllImport("ntdll.dll")]
    public static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returnLength);
    [DllImport("newdev.dll", EntryPoint="UpdateDriverForPlugAndPlayDevicesW", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UpdateDriverForPlugAndPlayDevices(IntPtr hwnd, string hardwareId, string infPath, uint flags, [MarshalAs(UnmanagedType.Bool)] out bool reboot);
}
'@

function Save-State { $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8 }
function Read-CodeIntegrity {
    $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer,8)
        $length=0
        $status=[DeckConfigNative]::NtQuerySystemInformation(103,$buffer,8,[ref]$length)
        if ($status -ne 0) { throw 'Could not query live Code Integrity state.' }
        $options=[Runtime.InteropServices.Marshal]::ReadInt32($buffer,4)
        [PSCustomObject]@{Options=$options; TestSigningActive=(($options -band 2) -ne 0)}
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
}
function Read-Gpu {
    $devices=@(Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like ($expectedHardware+'\*') })
    if ($devices.Count -ne 1) { throw 'Expected exactly one LCD Deck GPU.' }
    $values=@{}
    foreach ($p in @(Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId -KeyName @('DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_Service'))) { $values[$p.KeyName]=$p.Data }
    foreach ($key in @('DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_Service')) { if ($null -eq $values[$key]) { throw "Missing GPU property: $key" } }
    [PSCustomObject]@{
        InstanceId=$devices[0].InstanceId
        Name=$devices[0].FriendlyName
        ProblemCode=[int]$values['DEVPKEY_Device_ProblemCode']
        Version=[string]$values['DEVPKEY_Device_DriverVersion']
        Inf=[string]$values['DEVPKEY_Device_DriverInfPath']
        Service=[string]$values['DEVPKEY_Device_Service']
    }
}
function Read-SelectedFiles($gpu) {
    $image=[string](Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$gpu.Service) -Name ImagePath).ImagePath
    $path=[Environment]::ExpandEnvironmentVariables($image).Trim('"')
    if ($path.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)) { $path=Join-Path $env:SystemRoot $path.Substring(12) }
    if ($path.StartsWith('\??\')) { $path=$path.Substring(4) }
    $path=[IO.Path]::GetFullPath($path)
    $storeRoot=[IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'System32\DriverStore\FileRepository')).TrimEnd('\')+'\'
    if (-not $path.StartsWith($storeRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($path) -ne 'amdkmdag.sys') { throw 'Unexpected selected kernel image path.' }
    $config=Join-Path (Split-Path -Parent $path) 'amdgcf.dat'
    [PSCustomObject]@{KernelPath=$path; KernelSHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; ConfigurationPath=$config; ConfigurationSHA256=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash}
}
function Assert-Files($root,$files) {
    $absoluteRoot=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
    foreach ($entry in $files) {
        $path=[IO.Path]::GetFullPath((Join-Path $absoluteRoot $entry.Path))
        if (-not $path.StartsWith($absoluteRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'File manifest escapes its package.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "Package file hash mismatch: $($entry.Path)" }
    }
}
function Certificate-Present($storeName,$thumbprint) {
    $store=[Security.Cryptography.X509Certificates.X509Store]::new($storeName,'LocalMachine')
    $store.Open('ReadOnly')
    try { @($store.Certificates | Where-Object Thumbprint -eq $thumbprint).Count -gt 0 } finally { $store.Close() }
}
function Trust-Certificate($storeName,$certificate) {
    $store=[Security.Cryptography.X509Certificates.X509Store]::new($storeName,'LocalMachine')
    $store.Open('ReadWrite')
    try { $store.Add($certificate) } finally { $store.Close() }
}
function Bind-Driver($inf) {
    $reboot=$false
    $success=[DeckConfigNative]::UpdateDriverForPlugAndPlayDevices([IntPtr]::Zero,$expectedHardware,$inf,5,[ref]$reboot)
    $nativeError=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if (-not $success) { throw "PnP driver selection failed: $nativeError" }
    $reboot
}
function Stage-Inf($inf) {
    $messages=@(& pnputil.exe /add-driver $inf 2>&1)
    $result=$LASTEXITCODE
    $messages | Write-Host
    if ($result -notin @(0,3010)) { throw "Driver staging failed: $result" }
    @([regex]::Matches(($messages -join "`n"),'oem\d+\.inf') | ForEach-Object Value | Select-Object -Unique)
}
function Find-PublishedInf($inf,$published) {
    $hash=(Get-FileHash -LiteralPath $inf -Algorithm SHA256).Hash
    $matches=@($published | Where-Object { (Get-FileHash -LiteralPath (Join-Path $env:SystemRoot ('INF\'+$_)) -Algorithm SHA256).Hash -eq $hash })
    if ($matches.Count -ne 1) { throw 'Could not uniquely identify the staged candidate INF.' }
    [string]$matches[0]
}

try {
    $computer=Get-CimInstance Win32_ComputerSystem
    if ($computer.Manufacturer -ne 'Valve' -or $computer.Model -ne 'Jupiter') { throw 'The trial is restricted to the LCD Deck.' }
    $ci=Read-CodeIntegrity
    $gpu=Read-Gpu
    if (-not $ci.TestSigningActive) { throw 'This first trial requires Test Mode already active.' }
    $mainInf=Join-Path $signed.PackageDirectory $signed.MainInf
    $extensionInf=Join-Path $signed.PackageDirectory $signed.ExtensionInf
    $prototypeInf=Join-Path $prototype.PackageDirectory $prototype.MainInf
    if ($Mode -eq 'Check') {
        if (-not $state -or $gpu.Inf -ne $state.StagedMainInf -or $gpu.Version -ne $expectedVersion -or $gpu.ProblemCode -ne 0) { throw 'Candidate is not selected and healthy.' }
        $boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')
        if ($boot -eq $state.BootBeforeSelection) { throw 'A fresh boot has not occurred yet.' }
        $selectedFiles=Read-SelectedFiles $gpu
        if ($selectedFiles.KernelSHA256 -ne $expectedKernel -or $selectedFiles.ConfigurationSHA256 -ne $expectedConfig) { throw 'Selected driver files do not match the configuration-only candidate.' }
        & $signTool verify /kp /a /hash SHA256 $selectedFiles.KernelPath
        if ($LASTEXITCODE -ne 0) { throw 'Original kernel catalog verification failed.' }
        $state.Status='TestModeBootDriverStarted'
        $state.GpuAfterBoot=$gpu
        $state.SelectedFiles=$selectedFiles
        $state.VerifiedBoot=$boot
        $state.VerifiedCodeIntegrity=$ci
        $state.RebootRequired=$false
        Save-State
        Write-Output 'Candidate started on a fresh Test Mode boot. Hardware rendering and sleep/wake still need verification.'
        exit 0
    }
    Assert-Files $prototype.PackageDirectory $prototype.Files
    $backupRoot=Join-Path $projectRoot 'backups\display-32.0.11002.3007'
    $backupFiles=Get-Content -LiteralPath (Join-Path $projectRoot 'backups\file-hashes.json') -Raw | ConvertFrom-Json
    Assert-Files $backupRoot $backupFiles
    if ($Mode -eq 'RestorePrototype') {
        if (-not $state) { throw 'No candidate trial state exists.' }
        $bindingAttempted=$true
        [void](Bind-Driver $prototypeInf)
        $restored=Read-Gpu
        $prototypeInfHash=(Get-FileHash -LiteralPath $prototypeInf -Algorithm SHA256).Hash
        if ($restored.Version -ne $expectedVersion -or (Get-FileHash -LiteralPath (Join-Path $env:SystemRoot ('INF\'+$restored.Inf)) -Algorithm SHA256).Hash -ne $prototypeInfHash) { throw 'Prototype fallback was not selected.' }
        $restoredFiles=Read-SelectedFiles $restored
        if ($restoredFiles.KernelSHA256 -ne $prototypeKernel) { throw 'Fallback kernel is not the working prototype.' }
        $state.Status='PrototypeSelectedNeedsRestart'
        $state.RestoredGpu=$restored
        $state.RestoredFiles=$restoredFiles
        $state.RebootRequired=$true
        Save-State
        Write-Output 'Working prototype selected for the next Test Mode boot. Restart Windows.'
        exit 0
    }
    Assert-Files $signed.PackageDirectory $signed.Files
    if ($state -and $state.Status -eq 'CandidateSelectedNeedsRestart' -and $gpu.Inf -eq $state.StagedMainInf) {
        $selectedFiles=Read-SelectedFiles $gpu
        if ($selectedFiles.KernelSHA256 -eq $expectedKernel -and $selectedFiles.ConfigurationSHA256 -eq $expectedConfig) { Write-Output 'Candidate is already selected and awaiting a Test Mode restart.'; exit 0 }
        throw 'Previously selected candidate files differ.'
    }
    if ($gpu.Version -ne $expectedVersion -or $gpu.ProblemCode -ne 0 -or (Read-SelectedFiles $gpu).KernelSHA256 -ne $prototypeKernel) { throw 'The working prototype must be healthy before the first candidate trial.' }
    $certificateFile=Join-Path $trialRoot 'certificate\DeckLCD-Test.cer'
    $certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateFile)
    if ($certificate.Thumbprint -ne $signed.CertificateThumbprint -or $certificate.Subject -ne 'CN=Steam Deck LCD Configuration Trial') { throw 'Candidate certificate mismatch.' }
    $bcd=@(& bcdedit.exe /enum '{current}' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Could not read current boot settings.' }
    $testLine=@($bcd | Where-Object { [string]$_ -match '^\s*testsigning\s+' })
    $bcdTest=if ($testLine.Count -eq 1) { ([string]$testLine[0] -split '\s+')[-1] } else { 'Absent' }
    $state=[PSCustomObject]@{
        Status='PreparingCandidate'
        StartedAt=(Get-Date).ToString('o')
        GpuBefore=$gpu
        CodeIntegrityBefore=$ci
        BcdTestSigningBefore=$bcdTest
        BootSettingChanged=$false
        BootBeforeSelection=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')
        CertificateThumbprint=$certificate.Thumbprint
        RootCertificatePreviouslyPresent=(Certificate-Present 'Root' $certificate.Thumbprint)
        PublisherCertificatePreviouslyPresent=(Certificate-Present 'TrustedPublisher' $certificate.Thumbprint)
        StagedMainInf=$null
        StagedExtensionInf=$null
        StagedInfs=@()
        SelectedGpu=$null
        SelectedFiles=$null
        SelectedAt=$null
        CodeIntegrityAfterSelection=$null
        RestoredGpu=$null
        RestoredFiles=$null
        WindowsRequestedRestart=$false
        RebootRequired=$false
        LastError=$null
        NormalBootVerified=$false
        GpuAfterBoot=$null
        VerifiedBoot=$null
        VerifiedCodeIntegrity=$null
    }
    Save-State
    & bcdedit.exe /export (Join-Path $trialRoot 'bcd-before-candidate.bin')
    if ($LASTEXITCODE -ne 0) { throw 'Could not back up boot settings.' }
    $bcd | Set-Content -LiteralPath (Join-Path $trialRoot 'bcd-before-candidate.txt')
    if ($bcdTest -ne 'Yes') {
        & bcdedit.exe /set '{current}' TESTSIGNING ON
        if ($LASTEXITCODE -ne 0) { throw 'Could not preserve Test Mode for the next boot.' }
        $state.BootSettingChanged=$true
    }
    Trust-Certificate 'Root' $certificate
    Trust-Certificate 'TrustedPublisher' $certificate
    foreach ($name in @('decklcd-config.cat','decklcd-config-extension.cat')) {
        $signature=Get-AuthenticodeSignature -LiteralPath (Join-Path $signed.PackageDirectory $name)
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) { throw 'Local installation catalog signature failed.' }
    }
    & $signTool verify /pa /c (Join-Path $signed.PackageDirectory 'decklcd-config.cat') (Join-Path $signed.PackageDirectory 'B026204\amdgcf.dat')
    if ($LASTEXITCODE -ne 0) { throw 'Signed AE configuration verification failed.' }
    $mainPublished=@(Stage-Inf $mainInf)
    $state.StagedMainInf=Find-PublishedInf $mainInf $mainPublished
    $state.StagedInfs=@($mainPublished)
    Save-State
    $extensionPublished=@(Stage-Inf $extensionInf)
    $state.StagedExtensionInf=Find-PublishedInf $extensionInf $extensionPublished
    $state.StagedInfs=@(@($mainPublished)+@($extensionPublished) | Select-Object -Unique)
    Save-State
    & $signTool verify /kp /a /hash SHA256 (Join-Path $signed.PackageDirectory 'B026204\amdkmdag.sys')
    if ($LASTEXITCODE -ne 0) { throw 'Automatic original-kernel signature verification failed after staging.' }
    $state.Status='SelectingCandidate'
    Save-State
    if ($GuardNonce) {
        $guardDirectory=Join-Path $projectRoot ('guarded-reload\'+$GuardNonce)
        $guardPlan=Get-Content -LiteralPath (Join-Path $guardDirectory 'plan.json') -Raw | ConvertFrom-Json
        $guardStatus=Get-Content -LiteralPath (Join-Path $guardDirectory 'watchdog-status.json') -Raw | ConvertFrom-Json
        if ($guardPlan.Nonce -ne $GuardNonce -or $guardPlan.TimeoutSeconds -ne 180 -or $guardStatus.Nonce -ne $GuardNonce -or $guardStatus.Status -ne 'WaitingForReload') { throw 'The recovery watchdog is not armed for this reload.' }
        if (([datetime]::UtcNow-[datetime]::Parse($guardStatus.HeartbeatUtc).ToUniversalTime()).TotalSeconds -gt 10) { throw 'The recovery watchdog heartbeat is stale.' }
        if ((Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash -ne $guardPlan.ApplyScriptSHA256) { throw 'The trial helper changed after recovery preparation.' }
        $start=[PSCustomObject]@{Nonce=$GuardNonce; StartedUtc=[datetime]::UtcNow.ToString('o'); TimeoutSeconds=180; SelectionProcessId=$PID; BootBeforeReload=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')}
        $startPath=Join-Path $guardDirectory 'reload-start.json'
        if (Test-Path -LiteralPath $startPath) { throw 'This guarded reload was already started.' }
        $start | ConvertTo-Json | Set-Content -LiteralPath ($startPath+'.tmp') -Encoding UTF8
        [IO.File]::Move(($startPath+'.tmp'),$startPath)
    }
    $bindingAttempted=$true
    $state.WindowsRequestedRestart=Bind-Driver $mainInf
    Start-Sleep -Seconds 3
    $selected=Read-Gpu
    if ($selected.Version -ne $expectedVersion -or $selected.Inf -ne $state.StagedMainInf -or $selected.ProblemCode -notin @(0,43)) { throw 'Candidate selection did not match the expected INF/version/device status.' }
    $selectedFiles=Read-SelectedFiles $selected
    if ($selectedFiles.KernelSHA256 -ne $expectedKernel -or $selectedFiles.ConfigurationSHA256 -ne $expectedConfig) { throw 'Selected DriverStore files do not match the configuration-only candidate.' }
    $bcdAfter=@(& bcdedit.exe /enum '{current}' 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not @($bcdAfter | Where-Object { [string]$_ -match '^\s*testsigning\s+Yes\s*$' }).Count) { throw 'Test Mode is not enabled for the next boot.' }
    $state.Status='CandidateSelectedNeedsRestart'
    $state.SelectedGpu=$selected
    $state.SelectedFiles=$selectedFiles
    $state.CodeIntegrityAfterSelection=Read-CodeIntegrity
    $state.RebootRequired=$true
    $state.SelectedAt=(Get-Date).ToString('o')
    Save-State
    Write-Output "Configuration-only candidate selected as $($selected.Inf), current device code $($selected.ProblemCode). Ready for a Test Mode restart."
} catch {
    $failure=$_.Exception.Message
    if ($state) {
        $state.LastError=$failure
        $state.Status='CandidateSelectionFailed'
        if ($bindingAttempted -and $Mode -eq 'SelectTrial') {
            try {
                [void](Bind-Driver (Join-Path $prototype.PackageDirectory $prototype.MainInf))
                $restored=Read-Gpu
                $restoredFiles=Read-SelectedFiles $restored
                if ($restoredFiles.KernelSHA256 -ne $prototypeKernel) { throw 'Fallback kernel mismatch.' }
                $state | Add-Member -NotePropertyName RestoredGpu -NotePropertyValue $restored -Force
                $state | Add-Member -NotePropertyName RestoredFiles -NotePropertyValue $restoredFiles -Force
                $state.Status='PrototypeSelectedNeedsRestart'
                $state.RebootRequired=$true
            } catch { $state | Add-Member -NotePropertyName RecoveryError -NotePropertyValue $_.Exception.Message -Force }
        }
        Save-State
    }
    Write-Error $failure -ErrorAction Continue
    exit 1
} finally { Stop-Transcript | Out-Null }
