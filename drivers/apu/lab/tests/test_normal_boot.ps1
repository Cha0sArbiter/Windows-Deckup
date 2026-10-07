$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$source=Join-Path $projectRoot 'src\Manage-NormalBootTrial.ps1'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
# Extract only pure protocol/state functions; never execute the worker body.
foreach ($name in @('Read-Json','Write-Json','New-BootDecision','Assert-NormalSnapshot','Assert-FileSet','Assert-SharedSystemFiles','Invoke-BoundedPowerShell')) {
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($function.Extent.Text))
}
$testRoot=Join-Path $projectRoot ('normal-boot\protocol-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$token=[guid]::NewGuid().ToString(); $deadline=[datetime]::UtcNow.AddMinutes(3)
$before=$deadline.AddSeconds(-1); $after=$deadline.AddSeconds(1); $passed=0
function Assert-True($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action,$Message) {
    $thrown=$false
    try { & $Action | Out-Null } catch { $thrown=$true }
    Assert-True $thrown $Message
}
$keepPath=Join-Path $testRoot 'kept.json'
Assert-True (New-BootDecision -Path $keepPath -Token $token -Decision Keep -DeadlineUtc $deadline -NowUtc $before) 'Timely confirmation did not commit.'; $passed++
Assert-True (-not (New-BootDecision -Path $keepPath -Token $token -Decision Rollback -DeadlineUtc $deadline -NowUtc $after)) 'Recovery overwrote confirmation.'
Assert-True ((Read-Json $keepPath).Decision -eq 'Keep') 'Keep decision changed.'; $passed++
$rollbackPath=Join-Path $testRoot 'rollback.json'
Assert-True (New-BootDecision -Path $rollbackPath -Token $token -Decision Rollback -DeadlineUtc $deadline -NowUtc $after) 'Expired trial did not commit recovery.'; $passed++
Assert-True (-not (New-BootDecision -Path $rollbackPath -Token $token -Decision Keep -DeadlineUtc $deadline -NowUtc $before)) 'Confirmation overwrote committed recovery.'; $passed++
Assert-Throws { New-BootDecision -Path (Join-Path $testRoot 'early.json') -Token $token -Decision Rollback -DeadlineUtc $deadline -NowUtc $before } 'Recovery ran early.'; $passed++
Assert-Throws { New-BootDecision -Path (Join-Path $testRoot 'late.json') -Token $token -Decision Keep -DeadlineUtc $deadline -NowUtc $after } 'Late confirmation was accepted.'; $passed++
Assert-Throws { New-BootDecision -Path $keepPath -Token ([guid]::NewGuid().ToString()) -Decision Keep -DeadlineUtc $deadline -NowUtc $before } 'A different trial took the decision.'; $passed++
for ($iteration=0; $iteration -lt 50; $iteration++) {
    Write-Json (Join-Path $testRoot 'status.json') ([PSCustomObject]@{Nonce=$token; Iteration=$iteration})
    Assert-True ((Read-Json (Join-Path $testRoot 'status.json')).Iteration -eq $iteration) 'Atomic status replacement lost data.'
}
Assert-True (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.tmp*').Count -eq 0) 'Temporary protocol files leaked.'; $passed++
$candidateHash='EXPECTED_ORIGINAL_KERNEL'; $configHash='EXPECTED_DECK_CONFIG'
$plan=[PSCustomObject]@{BootBeforeUtc='previous-boot'}
function New-TestSnapshot {
    [PSCustomObject]@{BootUtc='new-boot'; CodeIntegrity=[PSCustomObject]@{TestSigningActive=$false}; Gpu=[PSCustomObject]@{Inf='oem56.inf'; Version='32.0.21043.21001'; ProblemCode=0}; SelectedFiles=[PSCustomObject]@{RegisteredInf='oem56.inf'; KernelSHA256=$candidateHash; ConfigurationSHA256=$configHash}}
}
Assert-NormalSnapshot (New-TestSnapshot) $plan; $passed++
$snapshot=New-TestSnapshot; $snapshot.BootUtc=$plan.BootBeforeUtc
Assert-Throws { Assert-NormalSnapshot $snapshot $plan } 'The previous boot was accepted.'; $passed++
$snapshot=New-TestSnapshot; $snapshot.CodeIntegrity.TestSigningActive=$true
Assert-Throws { Assert-NormalSnapshot $snapshot $plan } 'Test Mode was accepted as normal mode.'; $passed++
$snapshot=New-TestSnapshot; $snapshot.Gpu.ProblemCode=43
Assert-Throws { Assert-NormalSnapshot $snapshot $plan } 'An unhealthy GPU was acknowledged.'; $passed++
$snapshot=New-TestSnapshot; $snapshot.SelectedFiles.KernelSHA256='PATCHED_KERNEL'
Assert-Throws { Assert-NormalSnapshot $snapshot $plan } 'The patched kernel was accepted.'; $passed++
$snapshot=New-TestSnapshot; $snapshot.SelectedFiles.ConfigurationSHA256='OLD_CONFIG'
Assert-Throws { Assert-NormalSnapshot $snapshot $plan } 'A different configuration was accepted.'; $passed++
$snapshot=New-TestSnapshot; $snapshot.Gpu.Inf='oem50.inf'
Assert-Throws { Assert-NormalSnapshot $snapshot $plan } 'The fallback was accepted as the candidate.'; $passed++
$snapshot=New-TestSnapshot; $snapshot.SelectedFiles.RegisteredInf='oem50.inf'
Assert-Throws { Assert-NormalSnapshot $snapshot $plan } 'A pending fallback selection was accepted.'; $passed++
$payloadRoot=Join-Path $testRoot 'payload'
New-Item -ItemType Directory -Path (Join-Path $payloadRoot 'B026204') -Force | Out-Null
$payloadPath=Join-Path $payloadRoot 'B026204\sample.dat'
[IO.File]::WriteAllText($payloadPath,'verified test payload')
$files=@([PSCustomObject]@{Path='B026204\sample.dat'; SHA256=(Get-FileHash -LiteralPath $payloadPath).Hash})
Assert-True ((Assert-FileSet $payloadRoot $files) -eq 1) 'Valid staged bytes were rejected.'; $passed++
[IO.File]::WriteAllText($payloadPath,'changed test payload')
Assert-Throws { Assert-FileSet $payloadRoot $files } 'Changed staged bytes were accepted.'; $passed++
$missing=@([PSCustomObject]@{Path='B026204\missing.dat'; SHA256=$files[0].SHA256})
Assert-Throws { Assert-FileSet $payloadRoot $missing } 'Missing staged bytes were accepted.'; $passed++
$escape=@([PSCustomObject]@{Path='..\status.json'; SHA256=$files[0].SHA256})
Assert-Throws { Assert-FileSet $payloadRoot $escape } 'A staged path escaped its package.'; $passed++
$fakeInf=Join-Path $payloadRoot 'example.inf'
[IO.File]::WriteAllText($fakeInf,"[DS.System32]`r`nexample.dll`r`n")
$fakeCandidate=[PSCustomObject]@{PackageDirectory=$payloadRoot; MainInf='example.inf'; Files=@([PSCustomObject]@{Path='B026204\example.dll'; SHA256='SAME'})}
$fakePrototype=[PSCustomObject]@{Files=@([PSCustomObject]@{Path='B026204\example.dll'; SHA256='DIFFERENT'})}
Assert-Throws { Assert-SharedSystemFiles $fakeCandidate $fakePrototype } 'A shared component change was accepted.'; $passed++
$powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Nonce=$token
$child=Invoke-BoundedPowerShell -Arguments '-NoProfile -Command "exit 0"' -LogPrefix (Join-Path $testRoot 'child-success') -TimeoutMilliseconds 10000
Assert-True ($child.ExitCode -eq 0) 'A successful child lost its exit status.'; $passed++
$child=Invoke-BoundedPowerShell -Arguments '-NoProfile -Command "exit 7"' -LogPrefix (Join-Path $testRoot 'child-failure') -TimeoutMilliseconds 10000
Assert-True ($child.ExitCode -eq 7) 'A failing child lost its exit status.'; $passed++
$timeoutPrefix=Join-Path $testRoot 'child-timeout'
Assert-Throws { Invoke-BoundedPowerShell -Arguments '-NoProfile -Command "Start-Sleep -Seconds 5"' -LogPrefix $timeoutPrefix -TimeoutMilliseconds 500 } 'An unresponsive child was not stopped.'
$timedOut=Read-Json ($timeoutPrefix+'-process.json')
Assert-True (-not [bool](Get-Process -Id $timedOut.ProcessId -ErrorAction SilentlyContinue)) 'The timed-out child still runs.'; $passed++
Write-Output "$passed normal-boot protocol/state checks passed; no driver, task or boot-setting changes were performed."
