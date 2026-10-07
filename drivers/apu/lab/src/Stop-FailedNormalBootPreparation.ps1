$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Windows administrator rights are required.' }
$projectRoot=Split-Path -Parent $PSScriptRoot
$trialRoot=Join-Path $projectRoot 'normal-boot'
$active=Get-Content -LiteralPath (Join-Path $trialRoot 'active.json') -Raw | ConvertFrom-Json
if ($active.Nonce -ne 'b0aefb26-c5cd-46aa-82d2-ee29f426b1ea') { throw 'This repair is restricted to the failed copy-prompt trial.' }
$worker=Join-Path $PSScriptRoot 'Manage-NormalBootTrial.ps1'
$nativeSource=Join-Path $PSScriptRoot 'DeferredDeckDriver.cs'
$instance='PCI\VEN_1002&DEV_163F&SUBSYS_01231002&REV_AE\4&2E94418C&0&0041'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Read-Json','Write-Json','Initialize-Native','Read-CodeIntegrity','Read-Boot','Read-Gpu','Read-SelectedFiles','Read-Snapshot','Read-BcdTest','Set-BcdTest')) {
    $fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
Initialize-Native
New-Item -ItemType Directory -Path $trialRoot -Force | Out-Null
Start-Transcript -LiteralPath (Join-Path $active.Directory 'stop-copy-error.log') | Out-Null
$before=Read-Snapshot
if (-not $before.CodeIntegrity.TestSigningActive -or $before.Gpu.Inf -ne 'oem50.inf' -or $before.Gpu.ProblemCode -ne 0 -or $before.SelectedFiles.RegisteredInf -ne 'oem50.inf' -or $before.SelectedFiles.KernelSHA256 -ne 'E1B4DBFB807A59971BFC90E8139E35F96B4ADEDFD773695DBDCA5568B83D1ADF') { throw 'The unchanged working prototype must still be healthy before stopping this copy-only failure.' }
$taskName='SteamDeckDriverLab-NormalBootRecovery'
$task=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task -and $task.Actions.Arguments -notlike ('*'+$active.Nonce+'*')) { throw 'The task belongs to another trial.' }
# Preserve bootability before canceling the blocked installer and its guard.
Set-BcdTest ON
if ($task) { Stop-ScheduledTask -TaskName $taskName; Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
$process=Get-CimInstance Win32_Process -Filter 'ProcessId=9020' -ErrorAction SilentlyContinue
if ($process) {
    if ($process.Name -ne 'powershell.exe' -or $process.CommandLine -notlike ('*'+$worker+'*') -or $process.CommandLine -notmatch '-Mode\s+Prepare') { throw 'The blocked preparation process identity differs.' }
    Stop-Process -Id 9020 -Force
}
Write-Json (Join-Path $active.Directory 'control.json') ([PSCustomObject]@{Nonce=$active.Nonce; Phase='CancelledCopyFailure'})
$after=Read-Snapshot
if (-not $after.CodeIntegrity.TestSigningActive -or $after.Gpu.Inf -ne 'oem50.inf' -or $after.Gpu.ProblemCode -ne 0 -or $after.SelectedFiles.RegisteredInf -ne 'oem50.inf' -or $after.SelectedFiles.KernelSHA256 -ne 'E1B4DBFB807A59971BFC90E8139E35F96B4ADEDFD773695DBDCA5568B83D1ADF' -or (Read-BcdTest) -ne 'Yes') { throw 'Post-cancel prototype verification failed.' }
Write-Json (Join-Path $active.Directory 'cancelled-copy-failure.json') ([PSCustomObject]@{Nonce=$active.Nonce; Status='CancelledPrototypeUnchanged'; CompletedUtc=[datetime]::UtcNow.ToString('o'); Before=$before; After=$after; BcdTestSigning='Yes'; RecoveryTaskRemoved=(-not [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)); PreparationProcessStopped=(-not [bool](Get-Process -Id 9020 -ErrorAction SilentlyContinue))})
Write-Json (Join-Path $active.Directory 'status.json') ([PSCustomObject]@{Nonce=$active.Nonce; Status='CancelledPrototypeUnchanged'; UpdatedUtc=[datetime]::UtcNow.ToString('o')})
Write-Output 'Blocked preparation canceled. Working prototype verified, Test Mode ON, recovery task removed. No restart requested.'
