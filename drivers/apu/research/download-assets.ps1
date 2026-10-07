$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$auditDirectory = $PSScriptRoot
$catalog = Invoke-RestMethod -Uri 'https://www.asus.com/support/api/product.asmx/GetPDDrivers?website=us&model=RC73YA&cpu=&osid=52' -TimeoutSec 30
$catalog | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $auditDirectory 'current-asus-catalog.json')
$graphics = @($catalog.Result.Obj | Where-Object Name -eq 'Graphics')[0]
$latest = @($graphics.Files | Sort-Object ReleaseDate -Descending)[0]
$latest | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $auditDirectory 'selected-asus-package.json')
$packagePath = Join-Path $auditDirectory ([IO.Path]::GetFileName(([Uri]$latest.DownloadUrl.Global).AbsolutePath))
Write-Output "Downloading $($latest.Version) ($($latest.FileSize)) from ASUS."
if (-not (Test-Path -LiteralPath $packagePath)) {
    & curl.exe --fail --location --retry 2 --connect-timeout 30 --max-time 1200 --output $packagePath $latest.DownloadUrl.Global
    if ($LASTEXITCODE -ne 0) { throw "ASUS download failed: $LASTEXITCODE" }
}
$actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
if ($actualHash -ne $latest.sha256) { throw 'ASUS package SHA-256 does not match its official catalogue.' }
$signature = Get-AuthenticodeSignature -LiteralPath $packagePath
[PSCustomObject]@{Path=$packagePath; SHA256=$actualHash; SignatureStatus=[string]$signature.Status; Signer=$signature.SignerCertificate.Subject} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $auditDirectory 'package-verification.json')
Write-Output "ASUS hash verified. Signature: $($signature.Status); signer: $($signature.SignerCertificate.Subject)"
if ($signature.Status -ne 'Valid') { throw 'ASUS package signature is not valid.' }
