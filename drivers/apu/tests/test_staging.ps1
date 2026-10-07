$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$source=Join-Path $project 'installer\Stage-Package.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Staging helper parse failed.' }
# Extract only file verification; never execute staging/trust/PnP operations.
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-LocalHash'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$root=Join-Path ([IO.Path]::GetTempPath()) ('deckup-stage-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $file=Join-Path $root 'fixture.dat'
    [IO.File]::WriteAllText($file,'verified-data')
    $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if ((Assert-LocalHash $root 'fixture.dat' $hash) -ne $file) { throw 'Valid staged file was rejected.' }
    foreach ($case in @(@('fixture.dat',('0'*64)),@('missing.dat',$hash),@('../escape.dat',$hash))) {
        $threw=$false
        try { [void](Assert-LocalHash $root $case[0] $case[1]) } catch { $threw=$true }
        if (-not $threw) { throw 'Missing/corrupt/escaped package path was accepted.' }
    }
    Write-Output '4 staging file-integrity cases passed; no driver, trust or boot changes.'
} finally {
    # Delete only explicitly created files, then the empty verified temp folder.
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Force
}
