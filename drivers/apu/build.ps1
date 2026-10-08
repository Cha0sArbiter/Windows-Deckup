param(
    [string]$SourceDirectory='',
    [string]$OutputDirectory='',
    [string]$CacheRoot='',
    [string]$SignToolPath='',
    [string]$Inf2CatPath='',
    [string]$SevenZipPath='',
    [string]$Python='python',
    [switch]$RegisterVendorCatalogs
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $repoRoot 'build\apu' }
if (-not $CacheRoot) { $CacheRoot=Join-Path $repoRoot '.cache\apu' }
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory exists; choose a new output directory.' }
$spec=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifests\asus-32.0.21043.21001-config.json') -Raw | ConvertFrom-Json
if (-not $SignToolPath -or -not $Inf2CatPath -or (-not $SourceDirectory -and -not $SevenZipPath)) {
    $tools=& (Join-Path $repoRoot 'tools\Fetch-BuildTools.ps1')
    if (-not $SignToolPath) { $SignToolPath=$tools.SignTool }
    if (-not $Inf2CatPath) { $Inf2CatPath=$tools.Inf2Cat }
    if (-not $SevenZipPath) { $SevenZipPath=$tools.SevenZip }
}
$signature=Get-AuthenticodeSignature -LiteralPath $SignToolPath
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') { throw 'Microsoft SignTool publisher validation failed.' }
# This pinned WDK's Inf2Cat uses a Microsoft internal-build certificate
# without a public root. Authenticate it by the pinned official NuGet
# archive and exact executable hash; do not add that internal root to trust.
$toolPins=Get-Content -LiteralPath (Join-Path $repoRoot 'tools\toolchain.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $Inf2CatPath -Algorithm SHA256).Hash -ne $toolPins.wdk.executable_sha256) { throw 'Inf2Cat differs from the pinned Microsoft NuGet tool.' }
New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
if (-not $SourceDirectory) {
    $donor=Join-Path $CacheRoot 'asus-32.0.21043.21001.exe'
    if (-not (Test-Path -LiteralPath $donor)) {
        & curl.exe --fail --location --retry 3 --connect-timeout 30 --max-time 1200 --output $donor $spec.donor_url
        if ($LASTEXITCODE -ne 0) { throw 'ASUS donor download failed.' }
    }
    if ((Get-FileHash -LiteralPath $donor -Algorithm SHA256).Hash -ne $spec.package_sha256) { throw 'ASUS donor archive hash mismatch.' }
    $publisher=Get-AuthenticodeSignature -LiteralPath $donor
    if ($publisher.Status -ne 'Valid' -or $publisher.SignerCertificate.Subject -notmatch 'ASUSTeK COMPUTER INC') { throw 'ASUS donor publisher validation failed.' }
    $extract=Join-Path $CacheRoot 'donor'
    & $SevenZipPath x $donor "-o$extract" -y ($spec.source_subdirectory.Replace('/','\')+'\*') | Out-Host
    if ($LASTEXITCODE -notin @(0,1)) { throw 'ASUS display-package extraction failed.' }
    $SourceDirectory=Join-Path $extract $spec.source_subdirectory
}
$SourceDirectory=(Resolve-Path -LiteralPath $SourceDirectory).Path
if ((Get-FileHash -LiteralPath (Join-Path $SourceDirectory $spec.kernel) -Algorithm SHA256).Hash -ne $spec.kernel_sha256) { throw 'Unrecognized donor kernel.' }
$prepared=Join-Path $OutputDirectory 'prepared'
& $Python (Join-Path $PSScriptRoot 'lab\src\build_config_package.py') --source $SourceDirectory --output $prepared --manifest (Join-Path $PSScriptRoot 'manifests\asus-32.0.21043.21001-config.json')
if ($LASTEXITCODE -ne 0) { throw 'Configuration-only build/emulator checks failed.' }
& $Python (Join-Path $PSScriptRoot 'adapt_extension_reference.py') $prepared
if ($LASTEXITCODE -ne 0) { throw 'Renamed extension reference adaptation failed.' }
$report=Get-Content -LiteralPath (Join-Path $prepared 'package-report.json') -Raw | ConvertFrom-Json
$package=Join-Path $prepared 'WT6A_INF'
if ($report.kernel_modified -or $report.changed_executables.Count -ne 0 -or $report.candidate_sha256 -ne $spec.configuration_sha256) { throw 'Configuration-only invariants failed.' }

# On an ephemeral CI runner this proves automatic kernel-policy lookup as
# well as explicit vendor-catalog membership. Local builds default to no
# catalog/trust changes and still check explicit original-catalog membership.
if ($RegisterVendorCatalogs) {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Build-host catalog registration needs an administrator runner.' }
    foreach ($catalog in $report.original_catalogs) {
        $path=Join-Path (Join-Path $prepared 'original-catalogs') $catalog.path
        & $SignToolPath verify /kp $path | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Original vendor catalog failed kernel policy.' }
        & $SignToolPath catdb /u $path | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Build-host vendor catalog registration failed.' }
    }
}
$kernel=Join-Path $package $spec.kernel
& $SignToolPath verify /kp /c (Join-Path $prepared 'original-catalogs\u0202038.cat') $kernel | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Unchanged kernel failed explicit original-catalog verification.' }
if ($RegisterVendorCatalogs) {
    foreach ($file in Get-ChildItem -LiteralPath $package -Recurse -Filter '*.sys') {
        & $SignToolPath verify /kp /a /hash SHA256 $file.FullName | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Automatic kernel-policy verification failed: $($file.Name)" }
    }
}
$certRoot=Join-Path $OutputDirectory 'signing-private'
try {
    & $Python (Join-Path $PSScriptRoot 'lab\src\create_test_certificate.py') $certRoot --common-name 'Windows Deckup APU Package'
    if ($LASTEXITCODE -ne 0) { throw 'Setup certificate generation failed.' }
    $certFile=Join-Path $certRoot 'DeckLCD-Test.cer'
    $cert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($certFile)
    $pfx=Join-Path $certRoot 'DeckLCD-Test.pfx'
    $password=[IO.File]::ReadAllText((Join-Path $certRoot 'signing.password')).Trim()
    & $Inf2CatPath "/driver:$package" '/os:10_X64' | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Adapted catalogs failed Inf2Cat validation.' }
    foreach ($catalog in $report.original_catalogs) {
        if ($catalog.path -in @('u0202038.cat','amduw23e.cat')) { continue }
        Copy-Item -LiteralPath (Join-Path (Join-Path $prepared 'original-catalogs') $catalog.path) -Destination (Join-Path $package $catalog.path) -Force
    }
    foreach ($catalog in @('decklcd-config.cat','decklcd-config-extension.cat')) {
        & $SignToolPath sign /fd SHA256 /f $pfx /p $password (Join-Path $package $catalog) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Setup catalog signing failed: $catalog" }
        $signed=Get-AuthenticodeSignature -LiteralPath (Join-Path $package $catalog)
        if ($signed.SignerCertificate.Thumbprint -ne $cert.Thumbprint) { throw 'Adapted catalog signer mismatch.' }
    }
    foreach ($file in $report.files_before_catalog_regeneration) {
        if ($file.path.EndsWith('.cat',[StringComparison]::OrdinalIgnoreCase)) { continue }
        if ((Get-FileHash -LiteralPath (Join-Path $package $file.path) -Algorithm SHA256).Hash -ne $file.sha256) { throw "Unexpected payload change: $($file.path)" }
    }
    $bundle=Join-Path $OutputDirectory 'bundle'
    New-Item -ItemType Directory -Path $bundle | Out-Null
    Copy-Item -LiteralPath $package -Destination (Join-Path $bundle 'WT6A_INF') -Recurse
    Copy-Item -LiteralPath (Join-Path $prepared 'original-catalogs') -Destination (Join-Path $bundle 'original-catalogs') -Recurse
    Copy-Item -LiteralPath $certFile -Destination (Join-Path $bundle 'certificate.cer')
    Copy-Item -Path (Join-Path $PSScriptRoot 'installer\*') -Destination $bundle -Recurse
    New-Item -ItemType Directory -Path (Join-Path $bundle 'tools') | Out-Null
    foreach ($name in @('Fetch-BuildTools.ps1','toolchain.json')) { Copy-Item -LiteralPath (Join-Path $repoRoot ('tools\'+$name)) -Destination (Join-Path $bundle ('tools\'+$name)) }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'lab') -Recurse -File) {
        $relative=$file.FullName.Substring((Join-Path $PSScriptRoot 'lab').Length+1)
        if ($relative -match '(^|\\)(normal-boot|guarded-reload|backups|logs|__pycache__|private-[^\\]+)(\\|$)') { continue }
        $target=Join-Path (Join-Path $bundle 'lab') $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target
    }
    $installation=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'docs\installation.md') -Raw
    $installation=$installation.Replace('(results.md)','(https://github.com/Cha0sArbiter/Windows-Deckup/blob/main/drivers/apu/docs/results.md)').Replace('(build.md)','(https://github.com/Cha0sArbiter/Windows-Deckup/blob/main/drivers/apu/docs/build.md)').Replace('(../lab/README.md)','(https://github.com/Cha0sArbiter/Windows-Deckup/blob/main/drivers/apu/lab/README.md)')
    $installation | Set-Content -LiteralPath (Join-Path $bundle 'INSTALLATION.md') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $bundle 'LICENSE')
    $files=@(Get-ChildItem -LiteralPath (Join-Path $bundle 'WT6A_INF') -Recurse -File | ForEach-Object { [PSCustomObject]@{Path=$_.FullName.Substring((Join-Path $bundle 'WT6A_INF').Length+1).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
    $manifest=[ordered]@{Schema=1;InstallerSchema=2;SelectionPolicy='DeferredRestart';RecoveryGuardIncluded=$false;Status='PreparedNotInstalled';Variant='configuration-only';DriverVersion=$spec.driver_version;HardwareId=$spec.hardware_id;SourcePackageSHA256=$spec.package_sha256;KernelPath=$spec.kernel;KernelSHA256=$spec.kernel_sha256;ConfigurationSHA256=$spec.configuration_sha256;MainInf='decklcd-config.inf';ExtensionInf='decklcd-config-extension.inf';ExtensionCopyInfAdapted=$true;CertificateThumbprint=$cert.Thumbprint;CertificateSHA256=(Get-FileHash -LiteralPath (Join-Path $bundle 'certificate.cer') -Algorithm SHA256).Hash;KernelModified=$false;ChangedExecutables=@();KernelOriginalCatalogVerified=$true;BuildHostAutomaticKernelPolicyVerified=[bool]$RegisterVendorCatalogs;TargetHardwareInstallationVerified=$false;OriginalCatalogs=$report.original_catalogs;Files=$files;EmulatorChecks=$report.checks}
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $bundle 'manifest.json') -Encoding UTF8
    if (@(Get-ChildItem -LiteralPath $bundle -Recurse -File | Where-Object { $_.Extension -eq '.pfx' -or $_.Name.EndsWith('.password') }).Count) { throw 'Private signing material would be packaged.' }
    Write-Host "Prepared $($files.Count) driver files with unchanged ASUS executables: $bundle"
} finally {
    foreach ($name in @('DeckLCD-Test.pfx','signing.password')) {
        $privateFile=Join-Path $certRoot $name
        if (Test-Path -LiteralPath $privateFile) { Remove-Item -LiteralPath $privateFile -Force }
    }
    $password=$null
}
