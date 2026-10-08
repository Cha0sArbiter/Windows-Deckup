$ErrorActionPreference='Stop'
$installer=Join-Path (Split-Path -Parent $PSScriptRoot) 'installer'
. (Join-Path $installer 'Activation-Helpers.ps1')
Add-Type -Path (Join-Path $installer 'NextBootDriver.cs')
$passed=0
function Assert-True($Condition,[string]$Message) { if (-not $Condition) { throw $Message }; $script:passed++ }
function Assert-Throws([scriptblock]$Action,[string]$Message) {
    $threw=$false
    try { & $Action | Out-Null } catch { $threw=$true }
    Assert-True $threw $Message
}
# Only compile the native helper and exercise its pure validation/flag methods.
# Never call Inspect, SelectForReboot, or any device-installation API here.
$sizes=[DeckupNextBootDriver]::StructureSizes()
Assert-True (($sizes -join ',') -eq '32,584,1568') 'SetupAPI ABI differs from x64 Windows.'
$instance='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE\TEST-INSTANCE'
[DeckupNextBootDriver]::ValidateInstance($instance)
$passed++
foreach ($bad in @('',($instance.Replace('REV_AE','REV_AF')),($instance+'\EXTRA'),'PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE\')) {
    Assert-Throws { [DeckupNextBootDriver]::ValidateInstance($bad) } 'Invalid GPU instance was accepted.'
}
foreach ($old in @([uint32]0,[uint32]0x1000000,[uint32]0x1000800)) {
    $flags=[DeckupNextBootDriver]::InstallationFlags($old)
    Assert-True (($flags -band 0x20100) -eq 0x20100) 'Restart/deferred flags are missing.'
    Assert-True (($flags -band 0x1000000) -eq 0) 'Fresh installation file copies are suppressed.'
    Assert-True (($flags -band 0x800000) -ne 0) 'Quiet installation flag is missing.'
    Assert-True (($flags -band 0x800) -eq ($old -band 0x800)) 'An unrelated flag was lost.'
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('deckup-activation-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $testRoot 'B026204') -Force | Out-Null
$created=[Collections.Generic.List[string]]::new()
try {
    $files=@()
    foreach ($relative in @('decklcd-config.inf','decklcd-config.cat') + @(1..130 | ForEach-Object { 'B026204/fixture'+$_+'.dat' })) {
        $path=Join-Path $testRoot $relative
        [IO.File]::WriteAllText($path,'fixture-'+$relative)
        $created.Add($path)
        $files+=@([PSCustomObject]@{Path=$relative;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash})
    }
    $manifest=[PSCustomObject]@{MainInf='decklcd-config.inf';Files=$files}
    $inf=Join-Path $testRoot $manifest.MainInf
    Assert-True ((Assert-StagedMainPackage $manifest $inf) -eq 132) 'Valid staged files were rejected.'
    [IO.File]::WriteAllText($inf,'corrupt')
    Assert-Throws { Assert-StagedMainPackage $manifest $inf } 'A corrupt main INF was accepted.'
    [IO.File]::WriteAllText($inf,'fixture-decklcd-config.inf')
    Assert-Throws { Assert-StagedMainPackage $manifest (Join-Path $testRoot 'wrong.inf') } 'The wrong main INF identity was accepted.'
    $manifest.Files=@($files | Select-Object -Skip 1)
    Assert-Throws { Assert-StagedMainPackage $manifest $inf } 'An incomplete main-package layout was accepted.'
    $manifest.Files=$files
    $files[2].Path='B026204/../../escape.dat'
    Assert-Throws { Assert-StagedMainPackage $manifest $inf } 'A manifest path escaped the package.'
    $files[2].Path='B026204/fixture1.dat'
    $files[2].SHA256='0'*64
    Assert-Throws { Assert-StagedMainPackage $manifest $inf } 'A corrupt payload was accepted.'
    $hash=(Get-FileHash -LiteralPath $inf -Algorithm SHA256).Hash
    Assert-Throws { Find-PublishedInf $testRoot $hash } 'Missing published INF was accepted.'
    $one=Join-Path $testRoot 'oem123.inf'; $created.Add($one)
    Copy-Item -LiteralPath $inf -Destination $one
    Assert-True ((Find-PublishedInf $testRoot $hash) -eq $one) 'Dynamic published INF discovery failed.'
    $two=Join-Path $testRoot 'oem124.inf'; $created.Add($two)
    Copy-Item -LiteralPath $inf -Destination $two
    Assert-Throws { Find-PublishedInf $testRoot $hash } 'Ambiguous published INF was accepted.'
    $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $prefix=Join-Path $testRoot 'child'
    $created.Add($prefix+'.stdout.log'); $created.Add($prefix+'.stderr.log')
    Invoke-SelectionChild $powershell '-NoProfile -Command "exit 0"' $prefix 10000
    Assert-True (Test-Path -LiteralPath ($prefix+'.stdout.log')) 'Child logs were not written.'
    Assert-Throws { Invoke-SelectionChild $powershell '-NoProfile -Command "exit 7"' $prefix 10000 } 'A failed child was treated as success.'
    Assert-Throws { Invoke-SelectionChild $powershell '-NoProfile -Command "Start-Sleep -Seconds 10"' $prefix 500 } 'A hung child was not bounded.'
    Write-Output "$passed activation integrity/ABI/flag/process checks passed; no device, certificate, task, boot, or restart operations."
} finally {
    # Delete only the files created above and the two now-empty test directories.
    foreach ($file in $created) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath (Join-Path $testRoot 'B026204') -Force
    Remove-Item -LiteralPath $testRoot -Force
}
