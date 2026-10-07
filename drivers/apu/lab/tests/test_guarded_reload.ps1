$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$source=Join-Path $projectRoot 'src\Manage-GuardedReload.ps1'
$tokens=$null
$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
# Load only the actual JSON/decision functions; no task, driver or power code.
foreach ($name in @('Read-Json','Write-Json','New-ReloadDecision')) {
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($function.Extent.Text))
}
$testRoot=Join-Path $projectRoot ('guarded-reload\protocol-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$token=[guid]::NewGuid().ToString()
$deadline=[datetime]::UtcNow.AddMinutes(3)
$before=$deadline.AddSeconds(-1)
$after=$deadline.AddSeconds(1)
$passed=0
function Assert-True($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action,$Message) {
    $thrown=$false
    try { & $Action | Out-Null } catch { $thrown=$true }
    Assert-True $thrown $Message
}
$keepPath=Join-Path $testRoot 'kept.json'
Assert-True (New-ReloadDecision -Path $keepPath -Token $token -Decision Keep -DeadlineUtc $deadline -NowUtc $before) 'A timely acknowledgment should commit.'
$passed++
Assert-True (-not (New-ReloadDecision -Path $keepPath -Token $token -Decision Rollback -DeadlineUtc $deadline -NowUtc $after)) 'Recovery must not overwrite an acknowledgment.'
Assert-True ((Read-Json $keepPath).Decision -eq 'Keep') 'The first decision must survive.'
$passed++
$recoverPath=Join-Path $testRoot 'recover.json'
Assert-True (New-ReloadDecision -Path $recoverPath -Token $token -Decision Rollback -DeadlineUtc $deadline -NowUtc $after) 'An expired unanswered test should commit recovery.'
$passed++
Assert-True (-not (New-ReloadDecision -Path $recoverPath -Token $token -Decision Keep -DeadlineUtc $deadline -NowUtc $before)) 'A recovery decision must not be overwritten.'
Assert-True ((Read-Json $recoverPath).Decision -eq 'Rollback') 'Recovery decision changed.'
$passed++
Assert-Throws { New-ReloadDecision -Path (Join-Path $testRoot 'early.json') -Token $token -Decision Rollback -DeadlineUtc $deadline -NowUtc $before } 'Recovery ran early.'
$passed++
Assert-Throws { New-ReloadDecision -Path (Join-Path $testRoot 'late.json') -Token $token -Decision Keep -DeadlineUtc $deadline -NowUtc $after } 'A late acknowledgment was accepted.'
$passed++
Assert-Throws { New-ReloadDecision -Path $keepPath -Token ([guid]::NewGuid().ToString()) -Decision Keep -DeadlineUtc $deadline -NowUtc $before } 'A different trial reused the decision.'
$passed++
Assert-True (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.tmp').Count -eq 0) 'Decision temporary files leaked.'
$passed++
for ($iteration=0; $iteration -lt 50; $iteration++) {
    Write-Json (Join-Path $testRoot 'status.json') ([PSCustomObject]@{Nonce=$token; Iteration=$iteration})
    Assert-True ((Read-Json (Join-Path $testRoot 'status.json')).Iteration -eq $iteration) 'Atomic status replacement lost a committed value.'
}
$passed++
Write-Output "$passed guarded-reload protocol checks passed; no driver, task or power changes were performed."
