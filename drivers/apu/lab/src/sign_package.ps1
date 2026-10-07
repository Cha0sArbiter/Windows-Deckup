param(
    [Parameter(Mandatory=$true)][string]$PackageDirectory,
    [Parameter(Mandatory=$true)][string]$CertificateDirectory,
    [Parameter(Mandatory=$true)][string]$SignTool,
    [Parameter(Mandatory=$true)][string]$Inf2Cat
)
$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path -LiteralPath $PackageDirectory).Path
$certificateRoot = (Resolve-Path -LiteralPath $CertificateDirectory).Path
$signToolPath = (Resolve-Path -LiteralPath $SignTool).Path
$inf2CatPath = (Resolve-Path -LiteralPath $Inf2Cat).Path
$pfxPath = Join-Path $certificateRoot 'DeckLCD-Test.pfx'
$passwordPath = Join-Path $certificateRoot 'signing.password'
$password = [IO.File]::ReadAllText($passwordPath).Trim()
$kernelPath = Join-Path $packageRoot 'B026204\amdkmdag.sys'
$manifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests\asus-32.0.21043.21001.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$buildReport = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $packageRoot) 'build-report.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $kernelPath -Algorithm SHA256).Hash -ne $buildReport.patched_unsigned_kernel_sha256) {
    throw 'Patched kernel differs from the validated build report.'
}
Write-Output 'Signing the patched kernel with the local test certificate.'
& $signToolPath sign /fd SHA256 /f $pfxPath /p $password $kernelPath
if ($LASTEXITCODE -ne 0) { throw 'Kernel signing failed.' }
Write-Output 'Validating INF packages and rebuilding catalogs with Microsoft Inf2Cat.'
& $inf2CatPath "/driver:$packageRoot" '/os:10_X64' /verbose
if ($LASTEXITCODE -ne 0) { throw 'Inf2Cat signability validation failed.' }
$catalogs = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter '*.cat')
foreach ($catalog in $catalogs) {
    & $signToolPath sign /fd SHA256 /f $pfxPath /p $password $catalog.FullName
    if ($LASTEXITCODE -ne 0) { throw "Catalog signing failed: $($catalog.Name)" }
}
$certificatePath = Join-Path $certificateRoot 'DeckLCD-Test.cer'
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
$files = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object {
    [PSCustomObject]@{Path=$_.FullName.Substring($packageRoot.Length+1); SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
$signedReport = [PSCustomObject]@{
    DriverVersion=$manifest.driver_version
    HardwareId=$manifest.hardware_id
    PackageDirectory=$packageRoot
    CertificateThumbprint=$certificate.Thumbprint
    KernelSHA256=(Get-FileHash -LiteralPath $kernelPath -Algorithm SHA256).Hash
    MainInf='u0202038.inf'
    CatalogCount=$catalogs.Count
    Files=$files
}
$signedReport | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $packageRoot) 'signed-package.json')
Copy-Item -LiteralPath $certificatePath -Destination (Join-Path (Split-Path -Parent $packageRoot) 'DeckLCD-Test.cer') -Force
Remove-Item -LiteralPath $pfxPath -Force
Remove-Item -LiteralPath $passwordPath -Force
$password=$null
Write-Output 'Package signed and hashed. Private signing key files removed.'
