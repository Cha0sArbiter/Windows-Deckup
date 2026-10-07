$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$plan=Get-Content -LiteralPath (Join-Path $workspace 'deckup-cleanup-plan.json') -Raw | ConvertFrom-Json
$proof=Get-Content -LiteralPath (Join-Path $workspace 'deckup-hosted-artifact-verification.json') -Raw | ConvertFrom-Json
if ($plan.workspace -ne $workspace -or $proof.artifact_id -ne 11454186608 -or -not $proof.zip_crc_verified -or $proof.artifact_sha256 -ne 'd38a5181da2e09897b61f619cc6dfe2553d6b119475bfdbc65f6bc96ad13f15a' -or $proof.manifest_driver_files_verified -ne 151) { throw 'Verified hosting proof is required.' }
$repo=Join-Path $workspace 'Windows-Deckup'
$hosted=(& git -C $repo rev-parse origin/main).Trim()
if ($LASTEXITCODE -ne 0 -or $hosted -ne '6b54fe6fb69b8d0b676d3ec3f6eebc520aa2e262') { throw 'Unexpected hosted source commit.' }
& git -C $repo diff --exit-code origin/main
if ($LASTEXITCODE -ne 0) { throw 'Local source differs from verified hosted source.' }
$lab=Join-Path $workspace 'outputs\steamdeck-driver-lab'
$protected=@('Windows-Deckup\.git','Windows-Deckup\drivers','Windows-Deckup\tools','Windows-Deckup\docs','Windows-Deckup\.github','outputs\steamdeck-driver-lab\private-driver','outputs\steamdeck-driver-lab\private-config-install','outputs\steamdeck-driver-lab\backups','outputs\steamdeck-driver-lab\normal-boot','outputs\steamdeck-driver-lab\guarded-reload','outputs\steamdeck-driver-lab\src','outputs\steamdeck-driver-lab\private-config-package\original-catalogs','outputs\steamdeck-driver-lab\private-config-package\catalog-import','work\driver-audit\test-certificate','work\driver-audit\tools\sdk-buildtools') | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $workspace $_)) }
$allowed=@('Windows-Deckup\build','work\driver-audit\asus-extracted','work\driver-audit\AMD_Graphic_DriverOnly_ROG_AMD_B_V32.0.21043.21001_50567.exe','work\driver-audit\tools\sdk-buildtools.zip','work\driver-audit\tools\wdk.zip','work\driver-audit\tools\7zip-extra.7z','work\driver-audit\tools\7zr.exe','work\driver-audit\tools\7zip','work\driver-audit\tools\wdk-x86','work\driver-audit\python-libs','outputs\steamdeck-driver-lab\private-config-trial','outputs\steamdeck-driver-lab\private-config-package\WT6A_INF') | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $workspace $_)) }
function Assert-CleanupTarget([string]$Path) {
    $absolute=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($absolute -notin $allowed -or -not $absolute.StartsWith($workspace+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup target is outside the explicit workspace allowlist.' }
    foreach ($keep in $protected) {
        if ($absolute -eq $keep -or $absolute.StartsWith($keep+'\',[StringComparison]::OrdinalIgnoreCase) -or $keep.StartsWith($absolute+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup would overlap a retained source/recovery path.' }
    }
    $item=Get-Item -LiteralPath $absolute -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a reparse-point target.' }
    if ($item.PSIsContainer -and @(Get-ChildItem -LiteralPath $absolute -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Refusing a tree containing reparse points.' }
    $absolute
}
# Validate every target before deleting any directory. Also verify all local
# recovery package bytes, the stock backup and both original public certs.
$targets=@($plan.targets | ForEach-Object { Assert-CleanupTarget $_.path })
$verified=0
foreach ($relative in @('private-config-install\signed-config-package.json','private-driver\signed-package.json')) {
    $manifest=Get-Content -LiteralPath (Join-Path $lab $relative) -Raw | ConvertFrom-Json
    $root=[IO.Path]::GetFullPath($manifest.PackageDirectory).TrimEnd('\')
    if (-not $root.StartsWith($lab+'\',[StringComparison]::OrdinalIgnoreCase) -or @($manifest.Files).Count -ne 151) { throw 'Unexpected retained recovery manifest.' }
    foreach ($file in $manifest.Files) {
        $path=[IO.Path]::GetFullPath((Join-Path $root $file.Path))
        if (-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw 'Retained recovery package hash mismatch.' }
        $verified++
    }
}
$stock=Join-Path $lab 'backups\display-32.0.11002.3007'
foreach ($file in (Get-Content -LiteralPath (Join-Path $lab 'backups\file-hashes.json') -Raw | ConvertFrom-Json)) {
    $path=[IO.Path]::GetFullPath((Join-Path $stock $file.Path))
    if (-not $path.StartsWith($stock+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw 'Stock-driver backup hash mismatch.' }
    $verified++
}
$certificates=@(@{Path=(Join-Path $lab 'private-config-install\certificate\DeckLCD-Test.cer');Thumbprint='A1FE4F2E1EE372DE643A1CE45591A8681BCF0BBD'},@{Path=(Join-Path $workspace 'work\driver-audit\test-certificate\DeckLCD-Test.cer');Thumbprint='0C3AD4990F8F0694219B6FA503FA073E49CE3C50'})
foreach ($entry in $certificates) {
    if (([Security.Cryptography.X509Certificates.X509Certificate2]::new($entry.Path)).Thumbprint -ne $entry.Thumbprint) { throw 'Retained public certificate mismatch.' }
}
$receipt=[ordered]@{Status='RemovingVerifiedReproducibleFiles';StartedUtc=[datetime]::UtcNow.ToString('o');HostedSourceCommit=$hosted;BuildRun=37553577698;ArtifactId=11454186608;ArtifactSHA256=$proof.artifact_sha256;RecoveryFilesVerified=$verified;ProtectedPaths=$protected;Removed=@();BytesRemoved=0;FilesRemoved=0}
$receiptPath=Join-Path $workspace 'deckup-cleanup-receipt.json'
function Save-Receipt { $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8 }
Save-Receipt
foreach ($target in $targets) {
    $absolute=Assert-CleanupTarget $target
    $item=Get-Item -LiteralPath $absolute -Force
    $files=if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $absolute -Recurse -File -Force) } else { @($item) }
    $bytes=($files | Measure-Object -Property Length -Sum).Sum
    Remove-Item -LiteralPath $absolute -Recurse -Force
    if (Test-Path -LiteralPath $absolute) { throw 'A cleanup target remains after removal.' }
    $receipt.Removed+=@([PSCustomObject]@{Path=$absolute;Bytes=$bytes;Files=$files.Count})
    $receipt.BytesRemoved+=$bytes; $receipt.FilesRemoved+=$files.Count
    Save-Receipt
}
$receipt.Status='Completed'; $receipt.CompletedUtc=[datetime]::UtcNow.ToString('o'); Save-Receipt
[PSCustomObject]@{Status=$receipt.Status;GiBRemoved=[math]::Round($receipt.BytesRemoved/1GB,3);FilesRemoved=$receipt.FilesRemoved;RecoveryFilesVerified=$verified;Receipt=$receiptPath} | ConvertTo-Json
