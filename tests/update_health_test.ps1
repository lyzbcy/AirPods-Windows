$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$count=0
function Check([string]$Name,[bool]$Ok){
    if(!$Ok){throw "FAIL $Name"}
    $script:count++
    Write-Output "PASS $Name"
}
function Read-CheckBlock([string]$Path){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "PowerShell parse failed: $Path"}
    $assignment=$ast.Find({param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$check'},$true)
    if(!$assignment){throw "Health check missing: $Path"}
    Invoke-Expression ('$script:checkBlock = '+$assignment.Right.Extent.Text)
    return $script:checkBlock
}
function Start-Process {param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru)
    return $script:fakeProcess
}
function Test-Path {param($LiteralPath,$Path) return $true}
function Get-Content {param($LiteralPath,$Path,[switch]$Raw) throw 'simulated unreadable health marker'}
$script:r=[pscustomobject]@{token='0123456789abcdef0123456789abcdef';version='1.2.3'}
$script:healthFile='fixture.ready';$script:receipt='fixture.ready';$script:version='1.2.3';$script:token=$r.token
foreach($name in 'update-swap.ps1','build-deploy.ps1') {
    $script:fakeProcess=[pscustomobject]@{HasExited=$false;Killed=$false}
    $script:fakeProcess | Add-Member ScriptMethod Kill {$this.Killed=$true;$this.HasExited=$true}
    $script:fakeProcess | Add-Member ScriptMethod WaitForExit {param($timeout) return $true}
    $block=Read-CheckBlock (Join-Path $root ('scripts\'+$name))
    $threw=$false
    try {& $block 'fixture.exe'|Out-Null}catch{$threw=$true}
    Check "health_exception_kills_child_$name" ($threw -and $script:fakeProcess.Killed -and $script:fakeProcess.HasExited)
}
Remove-Item Function:\Start-Process,Function:\Test-Path,Function:\Get-Content
# Read the recovery function without running the swapper's top-level code.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\update-swap.ps1'),[ref]$tokens,[ref]$errors)
$recovery=$ast.Find({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-UpdateFailureRecovery'},$true)
if(!$recovery){throw 'Recovery function missing'}
. ([scriptblock]::Create($recovery.Extent.Text))
$work=Join-Path ([IO.Path]::GetTempPath()) ('AirPodsBuddy_recovery_test_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work|Out-Null
try {
    $exe=Join-Path $work 'AirPodsBuddy.exe'
    [IO.File]::WriteAllText($exe,'original fixture')
    $hash=(Get-FileHash -LiteralPath $exe).Hash
    $global:restartCount=0
    Invoke-UpdateFailureRecovery -Directory $work -OriginalHash $hash -OldProcess $null -Receipt (Join-Path $work 'blocked-receipt.txt') -Message 'health failed' `
        -WriteReceipt {param($path,$text) throw 'simulated receipt denial'} `
        -StartApp {param($path) $global:restartCount++}
    Check 'receipt_denial_does_not_block_old_app_restart' ($global:restartCount -eq 1)
} finally {Remove-Item -LiteralPath $work -Recurse -Force}
Write-Output "RESULT failures=0 tests=$count"
