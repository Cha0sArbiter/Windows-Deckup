# Register only unchanged Microsoft-signed vendor catalogs, then check the
# unchanged kernel through Windows' catalog database. No driver is installed,
# selected, restarted, or edited. No certificate or boot setting is changed.
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$taskRoot=Split-Path -Parent (Split-Path -Parent $projectRoot)
$trialRoot=Join-Path $projectRoot 'private-config-package'
$reportPath=Join-Path $trialRoot 'catalog-validation.json'
$packageReport=Get-Content -LiteralPath (Join-Path $trialRoot 'package-report.json') -Raw | ConvertFrom-Json
$signTool=Join-Path $taskRoot 'work\driver-audit\tools\sdk-buildtools\bin\10.0.26100.0\x64\signtool.exe'
$kernel=Join-Path $trialRoot 'WT6A_INF\B026204\amdkmdag.sys'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Catalog database registration requires Windows administrator privileges.'
}
if ($packageReport.kernel_modified -or $packageReport.kernel_sha256 -ne 'ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152') {
    throw 'Unexpected candidate kernel metadata.'
}
if ((Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash -ne $packageReport.kernel_sha256) {
    throw 'Kernel differs from the unchanged vendor binary.'
}
$toolSignature=Get-AuthenticodeSignature -LiteralPath $signTool
if ($toolSignature.Status -ne 'Valid' -or $toolSignature.SignerCertificate.Subject -notmatch 'Microsoft') {
    throw 'The Microsoft signing tool could not be authenticated.'
}
function Read-Gpu {
    $devices=@(Get-PnpDevice -Class Display | Where-Object { $_.InstanceId -like 'PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE\*' })
    if ($devices.Count -ne 1) { throw 'Expected the LCD Deck GPU.' }
    $properties=@{}
    foreach ($p in @(Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId -KeyName @('DEVPKEY_Device_ProblemCode','DEVPKEY_Device_DriverVersion','DEVPKEY_Device_DriverInfPath'))) {
        $properties[$p.KeyName]=$p.Data
    }
    [PSCustomObject]@{
        InstanceId=$devices[0].InstanceId
        ProblemCode=$properties['DEVPKEY_Device_ProblemCode']
        Version=$properties['DEVPKEY_Device_DriverVersion']
        Inf=$properties['DEVPKEY_Device_DriverInfPath']
    }
}
function Invoke-KernelVerification {
    # The pre-registration failure is expected. Windows PowerShell must
    # capture native stderr without converting that expected result into
    # a terminating PowerShell error before we inspect the process exit code.
    $ErrorActionPreference='Continue'
    $output=@(& $signTool verify /kp /a /hash SHA256 $kernel 2>&1 | ForEach-Object { "$_" })
    [PSCustomObject]@{Passed=($LASTEXITCODE -eq 0); Output=$output}
}
$validation=[ordered]@{
    Status='Started'
    StartedAt=(Get-Date).ToString('o')
    GpuBefore=(Read-Gpu)
    CatalogsAdded=@()
    NormalBootVerified=$false
    DriverBindingChanged=$false
    BootSettingsChanged=$false
    CertificateStoresChanged=$false
}
if (Test-Path -LiteralPath $reportPath) {
    $previousValidation=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $validation.CatalogsAdded=@($previousValidation.CatalogsAdded)
}
Start-Transcript -LiteralPath (Join-Path $trialRoot 'catalog-validation.log') -Force | Out-Null
try {
    $catalogRoot=[IO.Path]::GetFullPath((Join-Path $trialRoot 'original-catalogs')).TrimEnd('\')+'\'
    # Validate every input before registering any catalog.
    foreach ($entry in $packageReport.original_catalogs) {
        $path=[IO.Path]::GetFullPath((Join-Path $catalogRoot $entry.path))
        if (-not $path.StartsWith($catalogRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Catalog path escapes its directory.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'Original catalog hash mismatch.' }
        & $signTool verify /kp $path
        if ($LASTEXITCODE -ne 0) { throw "Original catalog failed Microsoft kernel-policy verification: $($entry.path)" }
    }
    & $signTool verify /kp /c (Join-Path $catalogRoot 'u0202038.cat') $kernel
    if ($LASTEXITCODE -ne 0) { throw 'Original catalog does not cover the unchanged kernel.' }
    $before=Invoke-KernelVerification
    $validation.AutomaticVerificationBeforePassed=$before.Passed
    $validation.AutomaticVerificationBefore=$before.Output
    $importRoot=Join-Path $trialRoot 'catalog-import'
    New-Item -ItemType Directory -Path $importRoot -Force | Out-Null
    if (-not $before.Passed) { foreach ($entry in $packageReport.original_catalogs) {
        $path=Join-Path $catalogRoot $entry.path
        $uniqueName='DeckLCD-Original-'+$entry.sha256.Substring(0,24)+'.cat'
        $copy=Join-Path $importRoot $uniqueName
        Copy-Item -LiteralPath $path -Destination $copy -Force
        $catalogMessages=@(& $signTool catdb /u $copy)
        if ($LASTEXITCODE -ne 0) { throw "Could not register original catalog: $($entry.path)" }
        $catalogMessages | Write-Output
        $assigned=[regex]::Match(($catalogMessages -join "`n"),'(?m)System assigned name:\s*(.+)$')
        $validation.CatalogsAdded+=@([PSCustomObject]@{
            OriginalPath=$entry.path
            ImportName=$uniqueName
            SHA256=$entry.sha256
            SystemAssignedName=if ($assigned.Success) { $assigned.Groups[1].Value.Trim() } else { $null }
        })
    } }
    $after=Invoke-KernelVerification
    $validation.AutomaticVerificationAfterPassed=$after.Passed
    $validation.AutomaticVerificationAfter=$after.Output
    if (-not $validation.AutomaticVerificationAfterPassed) { throw 'Automatic kernel-policy verification still fails.' }
    $validation.GpuAfter=Read-Gpu
    if (($validation.GpuBefore | ConvertTo-Json -Compress) -ne ($validation.GpuAfter | ConvertTo-Json -Compress)) {
        throw 'GPU state changed while checking catalogs; investigate before a driver trial.'
    }
    $validation.Status='OriginalKernelCatalogTrustVerified'
    $validation.CompletedAt=(Get-Date).ToString('o')
} catch {
    $validation.Status='Failed'
    $validation.Error=$_.Exception.Message
    throw
} finally {
    $validation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Stop-Transcript | Out-Null
}
