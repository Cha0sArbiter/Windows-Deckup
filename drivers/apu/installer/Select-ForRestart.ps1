param(
    [Parameter(Mandatory=$true)][string]$Instance,
    [Parameter(Mandatory=$true)][string]$PublishedInf,
    [Parameter(Mandatory=$true)][string]$RecoveryDirectory
)
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Selection requires administrator rights.' }
. (Join-Path $PSScriptRoot 'Activation-Helpers.ps1')
Add-Type -Path (Join-Path $PSScriptRoot 'NextBootDriver.cs')
[DeckupNextBootDriver]::ValidateInstance($Instance)
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
if ($manifest.InstallerSchema -ne 2 -or $manifest.SelectionPolicy -ne 'DeferredRestart' -or $manifest.Variant -ne 'configuration-only' -or $manifest.KernelModified -or $manifest.MainInf -ne 'decklcd-config.inf' -or $manifest.DriverVersion -ne '32.0.21043.21001') { throw 'Unexpected next-boot package.' }
$staged=[DeckupNextBootDriver]::ResolveStagedInf($PublishedInf)
[void](Assert-StagedMainPackage $manifest $staged)
$progressPath=Join-Path $RecoveryDirectory 'selection-progress.json'
$callback=[Action[string]]{param($step)
    [PSCustomObject]@{Step=$step;ProcessId=$PID;Utc=[datetime]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath $progressPath -Encoding UTF8
}
$result=[DeckupNextBootDriver]::SelectForReboot($Instance,$PublishedInf,$callback)
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $RecoveryDirectory 'selection-result.json') -Encoding UTF8
