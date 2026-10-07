param([ValidateSet('Prepare','Activate','SelectForRestart','Rollback')][string]$Mode='Prepare')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$logRoot=Join-Path $projectRoot 'logs'
$statePath=Join-Path $projectRoot 'installation-state.json'
$signedPath=Join-Path $projectRoot 'private-driver\signed-package.json'
$backupRoot=Join-Path $projectRoot 'backups\display-32.0.11002.3007'
$taskName='SteamDeckDriverLab-Activate-32.0.21043.21001'
$expectedHardwareId='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE'
$originalVersion='32.0.11002.3007'
$newVersion='32.0.21043.21001'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script with Windows administrator privileges.'
}
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logPath=Join-Path $logRoot ($Mode.ToLowerInvariant()+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
Start-Transcript -LiteralPath $logPath -Force | Out-Null

function Save-State($state) {
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
}
function Read-CodeIntegrity {
    if (-not ('DeckDriverNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DeckDriverNative {
    [DllImport("ntdll.dll")]
    public static extern int NtQuerySystemInformation(int infoClass, IntPtr buffer, int length, out int returnLength);
    [DllImport("newdev.dll", EntryPoint="UpdateDriverForPlugAndPlayDevicesW", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UpdateDriverForPlugAndPlayDevices(IntPtr hwnd, string hardwareId, string fullInfPath, uint flags, [MarshalAs(UnmanagedType.Bool)] out bool reboot);
}
'@
    }
    $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(8)
    try {
        [Runtime.InteropServices.Marshal]::WriteInt32($buffer,8)
        $length=0
        $status=[DeckDriverNative]::NtQuerySystemInformation(103,$buffer,8,[ref]$length)
        if ($status -ne 0) { throw ('Code Integrity query failed: 0x{0:X8}' -f $status) }
        $options=[Runtime.InteropServices.Marshal]::ReadInt32($buffer,4)
        return [PSCustomObject]@{Options=$options; TestSigningActive=(($options -band 2) -ne 0)}
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }
}
function Read-Gpu {
    $devices=@(Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like ($expectedHardwareId+'\*') })
    if ($devices.Count -ne 1) { throw 'Expected exactly one Steam Deck LCD AE GPU.' }
    $requiredKeys=@('DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_DriverInfPath')
    $properties=@{}
    foreach ($property in @(Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId -KeyName $requiredKeys)) {
        $properties[$property.KeyName]=$property.Data
    }
    foreach ($requiredKey in $requiredKeys) {
        if (-not $properties.ContainsKey($requiredKey) -or $null -eq $properties[$requiredKey]) { throw "Missing GPU property: $requiredKey" }
    }
    $drivers=@(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.DeviceID -eq $devices[0].InstanceId -and
        $_.DriverVersion -eq $properties['DEVPKEY_Device_DriverVersion'] -and
        $_.InfName -eq $properties['DEVPKEY_Device_DriverInfPath']
    })
    return [PSCustomObject]@{
        DeviceId=$devices[0].InstanceId
        Name=$devices[0].FriendlyName
        ErrorCode=[int]$properties['DEVPKEY_Device_ProblemCode']
        DriverVersion=[string]$properties['DEVPKEY_Device_DriverVersion']
        InfName=[string]$properties['DEVPKEY_Device_DriverInfPath']
        Signer=if ($drivers.Count) { $drivers[0].Signer } else { $null }
    }
}
function Assert-Files($root,$files) {
    $absoluteRoot=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
    foreach ($file in $files) {
        $path=[IO.Path]::GetFullPath((Join-Path $root $file.Path))
        if (-not $path.StartsWith($absoluteRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'File manifest escapes its package directory.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw "File hash mismatch: $($file.Path)" }
    }
}
function Cert-Present($storeName,$thumbprint) {
    $store=[Security.Cryptography.X509Certificates.X509Store]::new($storeName,'LocalMachine')
    $store.Open('ReadOnly')
    try { return @($store.Certificates | Where-Object Thumbprint -eq $thumbprint).Count -gt 0 }
    finally { $store.Close() }
}
function Change-Cert($storeName,$certificate,$add) {
    $store=[Security.Cryptography.X509Certificates.X509Store]::new($storeName,'LocalMachine')
    $store.Open('ReadWrite')
    try { if ($add) { $store.Add($certificate) } else { $store.Remove($certificate) } }
    finally { $store.Close() }
}
function Bind-Driver($infPath) {
    $reboot=$false
    $success=[DeckDriverNative]::UpdateDriverForPlugAndPlayDevices([IntPtr]::Zero,$expectedHardwareId,$infPath,5,[ref]$reboot)
    $errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if (-not $success) { throw "Windows driver binding failed: $errorCode" }
    return $reboot
}
function Remove-ActivationTask {
    $task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
}
function Restore-BootAndCertificate($state,$certificate) {
    if ($state.BootSettingChanged) {
        if ($state.OriginalBcdTestSigning -eq 'Yes') {
            & bcdedit.exe /set TESTSIGNING ON
        } elseif ($state.OriginalBcdTestSigning -eq 'No') {
            & bcdedit.exe /set TESTSIGNING OFF
        } else {
            & bcdedit.exe /deletevalue TESTSIGNING
        }
        if ($LASTEXITCODE -ne 0) { throw 'Could not restore the original test-signing boot setting.' }
    }
    if (-not $state.RootCertificatePreviouslyPresent) { Change-Cert 'Root' $certificate $false }
    if (-not $state.PublisherCertificatePreviouslyPresent) { Change-Cert 'TrustedPublisher' $certificate $false }
}

try {
    $computer=Get-CimInstance Win32_ComputerSystem
    if ($computer.Manufacturer -ne 'Valve' -or $computer.Model -ne 'Jupiter') { throw 'This experiment is only for the LCD Steam Deck.' }
    $ci=Read-CodeIntegrity
    $gpu=Read-Gpu
    $signed=Get-Content -LiteralPath $signedPath -Raw | ConvertFrom-Json
    if ($signed.DriverVersion -ne $newVersion -or $signed.HardwareId -ne $expectedHardwareId) { throw 'Unexpected signed-package metadata.' }
    $certificatePath=Join-Path $projectRoot 'private-driver\DeckLCD-Test.cer'
    $certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
    if ($certificate.Thumbprint -ne $signed.CertificateThumbprint) { throw 'Signing certificate does not match the built package.' }
    $state=if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } else { $null }
    $newInf=Join-Path $signed.PackageDirectory $signed.MainInf
    $oldInf=Join-Path $backupRoot 'u0403558.inf'
    if ($Mode -eq 'Prepare') {
        if ($state -and $state.Status -in @('QueuedForRestart','Activated','ActivationNeedsRestart','TrialNeedsRestart')) {
            Write-Output "Existing installation state: $($state.Status)"
            exit 0
        }
        if ($gpu.DriverVersion -ne $originalVersion) { throw 'Current display driver differs from the backed-up baseline.' }
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { throw 'An activation task already exists; refusing to replace it.' }
        Assert-Files $signed.PackageDirectory $signed.Files
        $backupFiles=Get-Content -LiteralPath (Join-Path $projectRoot 'backups\file-hashes.json') -Raw | ConvertFrom-Json
        Assert-Files $backupRoot $backupFiles
        $bcdText=@(& bcdedit.exe /enum 2>&1)
        if ($LASTEXITCODE -ne 0) { throw 'Could not read boot configuration.' }
        $bcdText | Set-Content -LiteralPath (Join-Path $projectRoot 'backups\bcd-before.txt')
        $testLine=@($bcdText | Where-Object { [string]$_ -match '^\s*testsigning\s+' })
        $originalBcdValue=if ($testLine.Count) { ([string]$testLine[0] -split '\s+')[-1] } else { 'Absent' }
        if ($originalBcdValue -notin @('Yes','No','Absent')) { throw 'Cannot interpret the existing test-signing setting.' }
        & bcdedit.exe /export (Join-Path $projectRoot 'backups\bcd-before.bin')
        if ($LASTEXITCODE -ne 0) { throw 'Could not back up boot configuration.' }
        $state=[PSCustomObject]@{
            Status='Preparing'
            StartedAt=(Get-Date).ToString('o')
            OriginalGpu=$gpu
            OriginalCodeIntegrity=$ci
            OriginalBcdTestSigning=$originalBcdValue
            BootSettingChanged=$false
            RootCertificatePreviouslyPresent=(Cert-Present 'Root' $certificate.Thumbprint)
            PublisherCertificatePreviouslyPresent=(Cert-Present 'TrustedPublisher' $certificate.Thumbprint)
            CertificateThumbprint=$certificate.Thumbprint
            StagedInf=$null
            StagedInfs=@()
            ActivationTask=$null
            LastError=$null
            ActivatedGpu=$null
            RebootRequired=$false
        }
        Save-State $state
        Change-Cert 'Root' $certificate $true
        Change-Cert 'TrustedPublisher' $certificate $true
        foreach ($checkFile in @((Join-Path $signed.PackageDirectory 'B026204\amdkmdag.sys'),(Join-Path $signed.PackageDirectory 'u0202038.cat'))) {
            $signature=Get-AuthenticodeSignature -LiteralPath $checkFile
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
                throw "Test signature verification failed: $checkFile"
            }
        }
        $stageOutput=@(& pnputil.exe /add-driver $newInf 2>&1)
        $stageExit=$LASTEXITCODE
        $stageOutput | Write-Output
        if ($stageExit -notin @(0,3010)) { throw "Driver staging failed: $stageExit" }
        $published=@([regex]::Matches(($stageOutput -join '\n'),'oem\d+\.inf') | ForEach-Object Value | Select-Object -Unique)
        $state.StagedInfs=@($published)
        $mainInfHash=(Get-FileHash -LiteralPath $newInf -Algorithm SHA256).Hash
        foreach ($publishedName in $published) {
            $publishedInfPath=Join-Path $env:SystemRoot ('INF\'+$publishedName)
            if ((Get-FileHash -LiteralPath $publishedInfPath -Algorithm SHA256).Hash -eq $mainInfHash) {
                $state.StagedInf=$publishedName
            }
        }
        if (-not $state.StagedInf) { throw 'Could not identify the staged display INF for rollback.' }
        if (-not $ci.TestSigningActive) {
            & bcdedit.exe /set TESTSIGNING ON
            if ($LASTEXITCODE -ne 0) { throw 'Windows rejected test-signing mode. No protection settings will be disabled automatically.' }
            $state.BootSettingChanged=($originalBcdValue -ne 'Yes')
            Save-State $state
        }
        $actionArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode Activate'
        $action=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument $actionArgs -WorkingDirectory $projectRoot
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
        $trigger.Delay='PT20S'
        $taskPrincipal=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        $task=New-ScheduledTask -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Description 'One-time activation of the locally validated Steam Deck LCD driver experiment; removes itself before activation.'
        Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
        $state.Status='QueuedForRestart'
        $state.ActivationTask=$taskName
        $state.RebootRequired=$true
        Save-State $state
        if ($ci.TestSigningActive) { Start-ScheduledTask -TaskName $taskName }
        Write-Output 'Driver staged. Current display binding is preserved. Activation is queued for the next Windows sign-in after restart.'
    } elseif ($Mode -eq 'Activate') {
        if (-not $state) { throw 'Prepare has not completed.' }
        Remove-ActivationTask
        $state.ActivationTask=$null
        Save-State $state
        if (-not $ci.TestSigningActive) { throw 'Test-signing mode is not active. Restart Windows before activation.' }
        Assert-Files $signed.PackageDirectory $signed.Files
        $state.Status='Activating'
        Save-State $state
        $reboot=Bind-Driver $newInf
        Start-Sleep -Seconds 5
        $gpu=Read-Gpu
        if ($gpu.DriverVersion -ne $newVersion -or $gpu.ErrorCode -ne 0) {
            $state | Add-Member -NotePropertyName FailedGpu -NotePropertyValue $gpu -Force
            Save-State $state
            $backupFiles=Get-Content -LiteralPath (Join-Path $projectRoot 'backups\file-hashes.json') -Raw | ConvertFrom-Json
            Assert-Files $backupRoot $backupFiles
            $state.RebootRequired=Bind-Driver $oldInf
            $restored=Read-Gpu
            $state.ActivatedGpu=$restored
            $state.RebootRequired=($state.RebootRequired -or $restored.ErrorCode -ne 0)
            throw "New GPU driver did not start cleanly (code $($gpu.ErrorCode)). Original driver selected; recovery code $($restored.ErrorCode), restart needed: $($state.RebootRequired)."
        }
        $state.Status=if ($reboot) { 'ActivationNeedsRestart' } else { 'Activated' }
        $state.ActivatedGpu=$gpu
        $state.RebootRequired=$reboot
        Save-State $state
        Write-Output "Activated driver $($gpu.DriverVersion); GPU error code $($gpu.ErrorCode); restart requested by Windows: $reboot"
    } elseif ($Mode -eq 'SelectForRestart') {
        if (-not $state) { throw 'Prepare has not completed.' }
        if (-not $ci.TestSigningActive) { throw 'Test-signing mode must be active before selecting the trial driver.' }
        if ($state.Status -ne 'ActivationFailed') { throw 'A fresh-boot trial requires a recorded failed live activation.' }
        Remove-ActivationTask
        Assert-Files $signed.PackageDirectory $signed.Files
        $backupFiles=Get-Content -LiteralPath (Join-Path $projectRoot 'backups\file-hashes.json') -Raw | ConvertFrom-Json
        Assert-Files $backupRoot $backupFiles
        $state | Add-Member -NotePropertyName PreviousActivationError -NotePropertyValue $state.LastError -Force
        $state | Add-Member -NotePropertyName TrialBootBefore -NotePropertyValue ((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')) -Force
        $state.Status='SelectingForRestart'
        Save-State $state
        $bindingReboot=Bind-Driver $newInf
        $selected=Read-Gpu
        if ($selected.DriverVersion -ne $newVersion -or $selected.InfName -ne $state.StagedInf) { throw 'Windows did not select the expected trial driver.' }
        if ($selected.ErrorCode -notin @(0,43)) { throw "Trial driver has unexpected device error $($selected.ErrorCode); inspect before restart." }
        $state | Add-Member -NotePropertyName SelectedGpu -NotePropertyValue $selected -Force
        $state | Add-Member -NotePropertyName WindowsBindingRequestedRestart -NotePropertyValue $bindingReboot -Force
        $state.Status='TrialNeedsRestart'
        $state.LastError=$null
        $state.ActivationTask=$null
        $state.RebootRequired=$true
        Save-State $state
        Write-Output "Trial driver $($selected.DriverVersion) selected; current device code $($selected.ErrorCode). Restart Windows to test initialization from startup. No automatic retry task is registered."
    } elseif ($Mode -eq 'Rollback') {
        if (-not $state) { throw 'No installation state to roll back.' }
        Remove-ActivationTask
        $backupFiles=Get-Content -LiteralPath (Join-Path $projectRoot 'backups\file-hashes.json') -Raw | ConvertFrom-Json
        Assert-Files $backupRoot $backupFiles
        if ($gpu.DriverVersion -ne $originalVersion -or $gpu.ErrorCode -ne 0) {
            & pnputil.exe /add-driver $oldInf
            if ($LASTEXITCODE -notin @(0,3010)) { throw 'Could not stage the original driver backup.' }
            $state.RebootRequired=Bind-Driver $oldInf
        }
        $restored=Read-Gpu
        if ($restored.DriverVersion -ne $originalVersion) { throw 'Original GPU driver was not selected; keep test mode and certificate until recovery succeeds.' }
        if ($restored.ErrorCode -ne 0) {
            $state.Status='RollbackNeedsRestart'
            $state.ActivationTask=$null
            $state.ActivatedGpu=$restored
            $state.RebootRequired=$true
            Save-State $state
            Write-Output "Original driver selected but device code $($restored.ErrorCode) persists. Restart Windows, then run Rollback.cmd again to complete package and trust cleanup."
            exit 0
        }
        $stagedNames=@($state.StagedInf)+@($state.StagedInfs)
        foreach ($stagedName in @($stagedNames | Select-Object -Unique)) {
            if ($stagedName -match '^oem\d+\.inf$' -and $stagedName -ne $restored.InfName) {
                & pnputil.exe /delete-driver $stagedName
                if ($LASTEXITCODE -notin @(0,3010)) { Write-Warning "Cached package $stagedName could not be removed; the original display driver is active." }
            }
        }
        Restore-BootAndCertificate $state $certificate
        $state.Status='RolledBack'
        $state.ActivationTask=$null
        $state.ActivatedGpu=$restored
        $state.RebootRequired=$true
        Save-State $state
        Write-Output 'Original driver restored and original boot-signing setting restored. Restart Windows to finish.'
    }
} catch {
    if ($state) {
        $state.Status=if ($Mode -eq 'Activate') { 'ActivationFailed' } else { 'Failed' }
        $state.LastError=$_.Exception.Message
        Save-State $state
        if ($Mode -eq 'Prepare') {
            Remove-ActivationTask
            try { Restore-BootAndCertificate $state $certificate } catch { Write-Warning $_.Exception.Message }
        }
    }
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally { Stop-Transcript | Out-Null }
