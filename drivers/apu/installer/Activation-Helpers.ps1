# Shared checks and bounded child execution. Loading this file changes no devices.
function Assert-StagedMainPackage($Manifest,[string]$Inf) {
    $root=[IO.Path]::GetFullPath((Split-Path -Parent $Inf)).TrimEnd('\')+'\'
    if ([IO.Path]::GetFileName($Inf) -ne $Manifest.MainInf) { throw 'The staged INF has an unexpected identity.' }
    $catalog=[IO.Path]::ChangeExtension($Manifest.MainInf,'.cat')
    $files=@($Manifest.Files | Where-Object {
        $_.Path -eq $Manifest.MainInf -or $_.Path -eq $catalog -or
        $_.Path.Replace('/','\').StartsWith('B026204\',[StringComparison]::OrdinalIgnoreCase)
    })
    if ($files.Count -ne 132) { throw 'Unexpected main-package file layout.' }
    foreach ($file in $files) {
        $path=[IO.Path]::GetFullPath((Join-Path $root $file.Path))
        if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'A staged file escapes its package.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.SHA256) { throw "Staged file mismatch: $($file.Path)" }
    }
    $files.Count
}

function Find-PublishedInf([string]$Directory,[string]$ExpectedHash) {
    $found=@(Get-ChildItem -LiteralPath $Directory -Filter 'oem*.inf' -File | Where-Object {
        $_.Name -match '^oem\d+\.inf$' -and
        (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq $ExpectedHash
    })
    if ($found.Count -ne 1) { throw "Expected one published INF with the exact package hash; found $($found.Count)." }
    $found[0].FullName
}

function Invoke-SelectionChild([string]$Executable,[string]$Arguments,[string]$LogPrefix,[int]$TimeoutMilliseconds=120000) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable; $start.Arguments=$Arguments
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
    $output=$null; $errorOutput=$null
    try {
        if (-not $process.Start()) { throw 'Could not start next-boot selection.' }
        [void]$process.Handle
        $output=$process.StandardOutput.ReadToEndAsync()
        $errorOutput=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            $process.Kill(); [void]$process.WaitForExit(5000)
            throw 'Selection timed out. It may have changed part of the device installation; inspect the recovery logs before restarting.'
        }
        $code=$process.ExitCode
        if ($null -eq $code) { throw 'Selection exit status is unavailable.' }
        if ($code -ne 0) { throw "Next-boot selection failed (exit $code); inspect the recovery logs before restarting." }
    } finally {
        if ($null -ne $output -and $output.IsCompleted -and -not $output.IsFaulted) { [IO.File]::WriteAllText(($LogPrefix+'.stdout.log'),$output.GetAwaiter().GetResult()) }
        if ($null -ne $errorOutput -and $errorOutput.IsCompleted -and -not $errorOutput.IsFaulted) { [IO.File]::WriteAllText(($LogPrefix+'.stderr.log'),$errorOutput.GetAwaiter().GetResult()) }
        $process.Dispose()
    }
}
