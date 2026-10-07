param([Parameter(Mandatory=$true)][string]$TrialDirectory)
$ErrorActionPreference='Stop'
$trialRoot=(Resolve-Path -LiteralPath $TrialDirectory).Path
$projectRoot=Split-Path -Parent $PSScriptRoot
$taskRoot=Split-Path -Parent (Split-Path -Parent $projectRoot)
$report=Get-Content -LiteralPath (Join-Path $trialRoot 'package-report.json') -Raw | ConvertFrom-Json
$packageRoot=(Resolve-Path -LiteralPath $report.package_directory).Path
if ($packageRoot -ne (Join-Path $trialRoot 'WT6A_INF')) { throw 'Unexpected package directory.' }
$kernel=Join-Path $packageRoot 'B026204\amdkmdag.sys'
$config=Join-Path $packageRoot 'B026204\amdgcf.dat'
$expectedKernel='ae975bbb56282be1471b9a91407f0155c087b619f99d2731d4e7989720522152'
$expectedConfig='7ee54354831bbf267c590636ffffd95fca91ff5455578151fa657bd5f9162717'
if ((Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash -ne $expectedKernel) { throw 'Kernel is not the unchanged ASUS original.' }
if ((Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -ne $expectedConfig) { throw 'Configuration differs from the emulated AE candidate.' }
$signTool=Join-Path $taskRoot 'work\driver-audit\tools\sdk-buildtools\bin\10.0.26100.0\x64\signtool.exe'
$inf2Cat=Join-Path $taskRoot 'work\driver-audit\tools\wdk-x86\Inf2Cat.exe'
$certRoot=Join-Path $trialRoot 'certificate'
$pfx=Join-Path $certRoot 'DeckLCD-Test.pfx'
$passwordFile=Join-Path $certRoot 'signing.password'
$certificateFile=Join-Path $certRoot 'DeckLCD-Test.cer'
$certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateFile)
if ($certificate.Subject -ne 'CN=Steam Deck LCD Configuration Trial') { throw 'Unexpected trial certificate.' }
$password=[IO.File]::ReadAllText($passwordFile).Trim()
try {
    foreach ($entry in $report.files_before_catalog_regeneration) {
        if (-not $entry.path.EndsWith('.cat',[StringComparison]::OrdinalIgnoreCase)) {
            if ((Get-FileHash -LiteralPath (Join-Path $packageRoot $entry.path) -Algorithm SHA256).Hash -ne $entry.sha256) {
                throw "Candidate file differs from the verified build: $($entry.path)"
            }
        }
    }
    & $inf2Cat "/driver:$packageRoot" '/os:10_X64'
    if ($LASTEXITCODE -ne 0) { throw 'Configuration-only package signability check failed.' }
    # Restore unchanged auxiliary catalogs after Inf2Cat. Only the display
    # and extension INFs/configuration were adapted; no executable is signed.
    foreach ($entry in $report.original_catalogs) {
        if ($entry.path -notin @('u0202038.cat','amduw23e.cat')) {
            $original=Join-Path (Join-Path $trialRoot 'original-catalogs') $entry.path
            if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'Original auxiliary catalog mismatch.' }
            Copy-Item -LiteralPath $original -Destination (Join-Path $packageRoot $entry.path) -Force
        }
    }
    foreach ($name in @('decklcd-config.cat','decklcd-config-extension.cat')) {
        & $signTool sign /fd SHA256 /f $pfx /p $password (Join-Path $packageRoot $name)
        if ($LASTEXITCODE -ne 0) { throw "Trial catalog signing failed: $name" }
        $signature=Get-AuthenticodeSignature -LiteralPath (Join-Path $packageRoot $name)
        if ($signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) { throw 'Catalog signer does not match the trial certificate.' }
    }
    if ((Get-FileHash -LiteralPath $kernel -Algorithm SHA256).Hash -ne $expectedKernel) { throw 'Kernel changed during catalog signing.' }
    & $signTool verify /kp /a /hash SHA256 $kernel
    if ($LASTEXITCODE -ne 0) { throw 'Unchanged kernel no longer passes automatic kernel-policy verification.' }
    $files=@(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object {
        [PSCustomObject]@{Path=$_.FullName.Substring($packageRoot.Length+1); SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    [PSCustomObject]@{
        Status='LocallySignedConfigurationOnlyPackagePrepared'
        DriverVersion='32.0.21043.21001'
        HardwareId='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE'
        PackageDirectory=$packageRoot
        MainInf='decklcd-config.inf'
        ExtensionInf='decklcd-config-extension.inf'
        KernelSHA256=$expectedKernel
        ConfigurationSHA256=$expectedConfig
        CertificateThumbprint=$certificate.Thumbprint
        CertificateSubject=$certificate.Subject
        CertificatePath=$certificateFile
        KernelModified=$false
        KernelCatalogPolicyVerified=$true
        NormalBootVerified=$false
        Installed=$false
        Files=$files
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $trialRoot 'signed-config-package.json') -Encoding UTF8
    Write-Output 'Signed only the two adapted catalogs. The kernel and all other executables remain original.'
} finally {
    Remove-Item -LiteralPath $pfx -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $passwordFile -Force -ErrorAction SilentlyContinue
    $password=$null
}
