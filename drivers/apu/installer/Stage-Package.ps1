$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run Stage.cmd as administrator.' }
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
$package=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'WT6A_INF')).Path
function Assert-LocalHash([string]$Root,[string]$Relative,[string]$Expected) {
    $path=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $path.StartsWith([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escapes its directory.' }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Expected) { throw "Package hash mismatch: $Relative" }
    $path
}
if ($manifest.Variant -ne 'configuration-only' -or $manifest.KernelModified -or $manifest.HardwareId -ne 'PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE' -or $manifest.KernelSHA256 -ne 'AE975BBB56282BE1471B9A91407F0155C087B619F99D2731D4E7989720522152' -or $manifest.ConfigurationSHA256 -ne '7EE54354831BBF267C590636FFFFD95FCA91FF5455578151FA657BD5F9162717') { throw 'Unrecognized configuration-only package.' }
if ($manifest.MainInf -ne 'decklcd-config.inf' -or $manifest.ExtensionInf -ne 'decklcd-config-extension.inf' -or @($manifest.Files).Count -ne 151 -or @($manifest.OriginalCatalogs).Count -ne 6) { throw 'Unexpected exact-build package layout.' }
foreach ($file in $manifest.Files) { [void](Assert-LocalHash $package $file.Path $file.SHA256) }
[void](Assert-LocalHash $package 'B026204/amdkmdag.sys' $manifest.KernelSHA256)
[void](Assert-LocalHash $package 'B026204/amdgcf.dat' $manifest.ConfigurationSHA256)
$originals=Join-Path $PSScriptRoot 'original-catalogs'
foreach ($catalog in $manifest.OriginalCatalogs) { [void](Assert-LocalHash $originals $catalog.path $catalog.sha256) }
$certificateFile=Assert-LocalHash $PSScriptRoot 'certificate.cer' $manifest.CertificateSHA256
$certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateFile)
if ($certificate.Thumbprint -ne $manifest.CertificateThumbprint -or $certificate.Subject -ne 'CN=Windows Deckup APU Package') { throw 'Setup certificate mismatch.' }
foreach ($name in @('decklcd-config.cat','decklcd-config-extension.cat')) {
    $signed=Get-AuthenticodeSignature -LiteralPath (Join-Path $package $name)
    if ($signed.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) { throw 'Setup catalog does not match the packaged public certificate.' }
}
$gpu=@(Get-PnpDevice -PresentOnly -Class Display | Where-Object { $_.InstanceId.StartsWith($manifest.HardwareId+'\',[StringComparison]::OrdinalIgnoreCase) })
if ($gpu.Count -ne 1) { throw 'Expected exactly one LCD Steam Deck AE GPU.' }
$values=@{}
Get-PnpDeviceProperty -InstanceId $gpu[0].InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_ProblemCode' | ForEach-Object { $values[$_.KeyName]=$_.Data }
if ($values['DEVPKEY_Device_ProblemCode'] -ne 0 -or $values['DEVPKEY_Device_DriverInfPath'] -notmatch '^oem\d+\.inf$') { throw 'Require a working, published display driver before staging.' }
$recovery=Join-Path (Join-Path $PSScriptRoot 'local-recovery') ([datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')+'-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $recovery 'original-driver') -Force | Out-Null
$state=[ordered]@{Status='Started';Device=$gpu[0].InstanceId;OriginalInf=$values['DEVPKEY_Device_DriverInfPath'];DriverBindingChanged=$false;BootSettingsChanged=$false;RecoveryTimerCreated=$false;CertificatesAdded=@();CatalogsRegistered=@();StagingOutput=@()}
function Save-State { $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $recovery 'staging-state.json') -Encoding UTF8 }
Save-State
try {
    & pnputil.exe /export-driver $state.OriginalInf (Join-Path $recovery 'original-driver') | Out-Host
    if ($LASTEXITCODE -ne 0 -or @(Get-ChildItem -LiteralPath (Join-Path $recovery 'original-driver') -Recurse -Filter '*.inf').Count -eq 0) { throw 'Original display-driver export failed.' }
    $tools=& (Join-Path $PSScriptRoot 'tools\Fetch-BuildTools.ps1') -OnlySdk -CacheRoot (Join-Path $PSScriptRoot '.cache\toolchain')
    foreach ($catalog in $manifest.OriginalCatalogs) {
        $path=Join-Path $originals $catalog.path
        & $tools.SignTool verify /kp $path | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Original vendor catalog failed kernel signing policy.' }
    }
    foreach ($catalog in $manifest.OriginalCatalogs) {
        & $tools.SignTool catdb /u (Join-Path $originals $catalog.path) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Vendor catalog database registration failed.' }
        $state.CatalogsRegistered+=@($catalog); Save-State
    }
    foreach ($file in Get-ChildItem -LiteralPath $package -Recurse -Filter '*.sys') {
        & $tools.SignTool verify /kp /a /hash SHA256 $file.FullName | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Unchanged executable failed automatic kernel policy: $($file.Name)" }
    }
    foreach ($storeName in @('Root','TrustedPublisher')) {
        $store=[Security.Cryptography.X509Certificates.X509Store]::new($storeName,'LocalMachine')
        $store.Open('ReadWrite')
        try {
            if (@($store.Certificates | Where-Object Thumbprint -eq $certificate.Thumbprint).Count -eq 0) { $store.Add($certificate); $state.CertificatesAdded+=@($storeName); Save-State }
        } finally { $store.Close() }
    }
    foreach ($name in @($manifest.ExtensionInf,$manifest.MainInf)) {
        $output=@(& pnputil.exe /add-driver (Join-Path $package $name) 2>&1 | ForEach-Object { "$_" })
        $exit=$LASTEXITCODE
        $state.StagingOutput+=@($output); Save-State
        $output | Write-Host
        if ($exit -notin @(0,3010)) { throw "Driver staging failed: $name ($exit)" }
    }
    $after=(Get-PnpDeviceProperty -InstanceId $gpu[0].InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath').Data
    if ($after -ne $state.OriginalInf) { throw 'Unexpected binding change while staging without /install.' }
    $state.Status='StagedNotSelected'; Save-State
    Write-Host "Staged only. Your display driver binding and boot settings are unchanged. Recovery record: $recovery"
} catch { $state.Status='StagingFailed'; $state.Error="$($_.Exception.Message)"; Save-State; throw }
