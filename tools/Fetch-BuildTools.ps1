param([string]$CacheRoot=(Join-Path (Split-Path -Parent $PSScriptRoot) '.cache\toolchain'),[switch]$OnlySdk)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$pins=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
function Get-PinnedFile($Spec,[string]$Name) {
    $path=Join-Path $CacheRoot $Name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "Downloading pinned tool: $Name"
        & curl.exe --fail --location --retry 3 --connect-timeout 30 --max-time 1200 --output $path $Spec.url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Name" }
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Spec.sha256) { throw "Tool hash mismatch: $Name" }
    $path
}
function Get-NugetTool($Spec,[string]$Name) {
    $archive=Get-PinnedFile $Spec ($Name+'.nupkg')
    $target=Join-Path $CacheRoot $Name
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.StartsWith($Spec.prefix,[StringComparison]::Ordinal) -or $entry.FullName.EndsWith('/')) { continue }
            $relative=$entry.FullName.Substring($Spec.prefix.Length)
            $output=[IO.Path]::GetFullPath((Join-Path $target $relative))
            if (-not $output.StartsWith([IO.Path]::GetFullPath($target).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'NuGet tool entry escapes output.' }
            New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$output,$true)
        }
    } finally { $zip.Dispose() }
    $executable=Join-Path $target $Spec.executable
    if (-not (Test-Path -LiteralPath $executable)) { throw "Tool missing from pinned NuGet package: $Name" }
    $executable
}
$sdk=Get-NugetTool $pins.sdk 'sdk'
$signature=Get-AuthenticodeSignature -LiteralPath $sdk
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') { throw 'Pinned SignTool publisher validation failed.' }
if ($OnlySdk) { [PSCustomObject]@{SignTool=$sdk}; return }
$wdk=Get-NugetTool $pins.wdk 'wdk'
$sevenzr=Get-PinnedFile $pins.sevenzr '7zr.exe'
$extra=Get-PinnedFile $pins.sevenzip '7zip-extra.7z'
$sevenDir=Join-Path $CacheRoot '7zip'
& $sevenzr x $extra "-o$sevenDir" -y | Out-Host
if ($LASTEXITCODE -ne 0) { throw '7-Zip tool extraction failed.' }
$seven=Join-Path $sevenDir 'x64\7za.exe'
if (-not (Test-Path -LiteralPath $seven)) { throw 'Pinned x64 7-Zip tool missing.' }
[PSCustomObject]@{SignTool=$sdk; Inf2Cat=$wdk; SevenZip=$seven}
