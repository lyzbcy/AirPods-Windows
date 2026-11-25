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
# Backup pruning touches only the copies this module wrote and keeps the newest ones.
Import-Module (Join-Path $root 'scripts\UpdateCore.psm1') -Force
$work=Join-Path ([IO.Path]::GetTempPath()) ('AirPodsBuddy_prune_test_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work|Out-Null
try {
    $exe=Join-Path $work 'AirPodsBuddy.exe'
    [IO.File]::WriteAllText($exe,'installed fixture')
    $names=@()
    foreach($i in 1..4){
        $p=Join-Path $work ('AirPodsBuddy.exe.backup-'+[guid]::NewGuid().ToString('N'))
        $names+=$p;[IO.File]::WriteAllText($p,'old '+$i)
        [IO.File]::SetLastWriteTimeUtc($p,[DateTime]::new(2026,1,1,0,0,$i,[DateTimeKind]::Utc))
    }
    $stranger=Join-Path $work ('AirPodsBuddy.exe.backup-'+[guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText((Join-Path $work 'AirPodsBuddy.exe.backup-notours'),'user file')
    [IO.File]::WriteAllText((Join-Path $work 'AirPodsBuddy.exe.stage-x'),'leftover')
    [IO.File]::WriteAllText((Join-Path $work ('Other.exe.backup-'+[guid]::NewGuid().ToString('N'))),'other app')
    $removed=Remove-UpdateBackups -Destination $exe -Keep 2
    Check 'prune_removes_only_the_oldest_own_backups' ($removed.Count -eq 2 -and !(Test-Path -LiteralPath $names[0]) -and !(Test-Path -LiteralPath $names[1]))
    Check 'prune_keeps_newest_backups_installed_exe_and_foreign_files' (
        (Test-Path -LiteralPath $names[2]) -and (Test-Path -LiteralPath $names[3]) -and (Test-Path -LiteralPath $exe) -and
        (Test-Path -LiteralPath (Join-Path $work 'AirPodsBuddy.exe.backup-notours')) -and (Test-Path -LiteralPath (Join-Path $work 'AirPodsBuddy.exe.stage-x')) -and
        @(Get-ChildItem -LiteralPath $work -Filter 'Other.exe.backup-*').Count -eq 1)
    $again=Remove-UpdateBackups -Destination $exe -Keep 2
    Check 'prune_is_idempotent' ($again.Count -eq 0 -and @(Get-ChildItem -LiteralPath $work -Filter 'AirPodsBuddy.exe.backup-*').Count -eq 3)
    $none=Remove-UpdateBackups -Destination (Join-Path $work 'Missing.exe') -Keep 2
    Check 'prune_without_backups_returns_empty' ($none.Count -eq 0)
    [IO.File]::WriteAllText($stranger,'locked fixture')
    [IO.File]::SetLastWriteTimeUtc($stranger,[DateTime]::new(2025,12,31,0,0,0,[DateTimeKind]::Utc))
    $locked=[IO.File]::Open($stranger,'Open','Read','None')
    try {
        $kept=Remove-UpdateBackups -Destination $exe -Keep 1
    } finally { $locked.Dispose() }
    Check 'prune_skips_a_backup_it_cannot_delete_without_failing' (
        $kept.Count -eq 1 -and (Test-Path -LiteralPath $stranger) -and (Test-Path -LiteralPath $names[3]) -and !(Test-Path -LiteralPath $names[2]))
} finally {Remove-Item -LiteralPath $work -Recurse -Force}
Write-Output "RESULT failures=0 tests=$count"
