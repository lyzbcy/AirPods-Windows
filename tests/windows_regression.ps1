$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module (Join-Path $root 'scripts\UpdateCore.psm1') -Force
Import-Module (Join-Path $root 'scripts\RepairCore.psm1') -Force
$work=Join-Path $root ('verification\2026-09-26-all\ps-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$count=0
function Check([string]$Name,[bool]$Ok){if(!$Ok){throw "FAIL $Name"};$script:count++;Write-Output "PASS $Name"}
function MustThrow([scriptblock]$Code){try{&$Code|Out-Null;return $false}catch{return $true}}
$candidate=Join-Path $work 'new.exe';$installed=Join-Path $work 'installed.exe'
[IO.File]::WriteAllText($candidate,'new candidate fixture');[IO.File]::WriteAllText($installed,'original fixture')
$hash=(Get-FileHash $candidate).Hash
Check 'bad_hash_does_not_modify_install' ((MustThrow {Invoke-UpdateTransaction $candidate $installed ('0'*64) {$true}}) -and (Get-Content $installed -Raw) -eq 'original fixture')
Check 'health_failure_restores_original' ((MustThrow {Invoke-UpdateTransaction $candidate $installed $hash {$false}}) -and (Get-Content $installed -Raw) -eq 'original fixture')
Check 'health_exception_restores_original' ((MustThrow {Invoke-UpdateTransaction $candidate $installed $hash {throw 'crash'}}) -and (Get-Content $installed -Raw) -eq 'original fixture')
$success=Invoke-UpdateTransaction $candidate $installed $hash {$true}
Check 'healthy_update_preserves_backup' ($success.Status -eq 'ok' -and (Get-Content $installed -Raw) -eq 'new candidate fixture' -and (Get-Content $success.Backup -Raw) -eq 'original fixture')
$corruptTarget=Join-Path $work 'corrupt-backup-test.exe'
[IO.File]::WriteAllText($corruptTarget,'original fixture')
$message=''
try {
 Invoke-UpdateTransaction $candidate $corruptTarget $hash {
  Get-ChildItem -LiteralPath $work -Filter 'corrupt-backup-test.exe.backup-*' | ForEach-Object { [IO.File]::WriteAllText($_.FullName,'corrupt backup') }
  return $false
 } | Out-Null
} catch {$message=$_.Exception.Message}
Check 'corrupt_backup_explicit_failure_not_false_rollback' ($message -like 'ROLLBACK_FAILED:*' -and (Get-Content $corruptTarget -Raw) -eq 'new candidate fixture')
$release=[pscustomobject]@{draft=$false;prerelease=$false;tag_name='v1.9.99';assets=@([pscustomobject]@{name='AirPodsBuddy-Windows.zip';browser_download_url='https://github.com/lyzbcy/AirPods-Windows/releases/download/v1.9.99/AirPodsBuddy-Windows.zip';digest=('sha256:'+'a'*64)})}
Check 'trusted_metadata_and_digest_accepted' ((Get-ApprovedRelease '1.9.19' {$release}).Version -eq '1.9.99')
$release.assets[0].digest=''
Check 'missing_digest_rejected' (MustThrow {Get-ApprovedRelease '1.9.19' {$release}})
$release.assets[0].digest='sha256:'+'a'*64;$release.assets[0].browser_download_url='https://evil.invalid/a.zip'
Check 'foreign_asset_host_rejected' (MustThrow {Get-ApprovedRelease '1.9.19' {$release}})
$release.draft=$true
Check 'draft_release_rejected' (MustThrow {Get-ApprovedRelease '1.9.19' {$release}})
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-TestZip([string]$Name,[string]$Entry,[string]$Content){
 $zip=Join-Path $work $Name;$z=[IO.Compression.ZipFile]::Open($zip,'Create')
 try{$e=$z.CreateEntry($Entry);$writer=New-Object IO.StreamWriter($e.Open());try{$writer.Write($Content)}finally{$writer.Dispose()}}finally{$z.Dispose()};return $zip
}
$zip=New-TestZip 'traversal.zip' '../escape.exe' 'MZfixture'
Check 'zip_traversal_rejected' (MustThrow {Expand-VerifiedUpdate $zip (Get-FileHash $zip).Hash (Join-Path $work 'bad-unpack')})
$zip=New-TestZip 'invalid.zip' 'AirPodsBuddy.exe' 'not-pe'
Check 'non_pe_candidate_rejected' (MustThrow {Expand-VerifiedUpdate $zip (Get-FileHash $zip).Hash (Join-Path $work 'invalid-unpack')})
$zip=New-TestZip 'valid.zip' 'AirPodsBuddy.exe' 'MZfixture'
$exe=Expand-VerifiedUpdate $zip (Get-FileHash $zip).Hash (Join-Path $work 'valid-unpack')
Check 'verified_archive_extracts_exact_executable' ((Get-Content $exe -Raw) -eq 'MZfixture')
$script:enabled=0
$id='BTHENUM\fixture';$ep='{0.0.0.00000000}.{fixture}'
Check 'repair_failure_reenables_target' ((MustThrow {Invoke-TargetedRepair $id $ep {throw 'disable failed'} {$script:enabled++} { @() } {}}) -and $enabled -eq 1)
Check 'capture_only_not_success' (!(Invoke-TargetedRepair $id $ep {} {} {@('{0.0.1.00000000}.{fixture}')} {}))
Check 'different_render_not_success' (!(Invoke-TargetedRepair $id $ep {} {} {@('{0.0.0.00000000}.{other}')} {}))
Check 'exact_active_render_success' (Invoke-TargetedRepair $id $ep {} {} {@($ep)} {})
Check 'broad_device_repair_rejected' (MustThrow {Invoke-TargetedRepair '*' $ep {} {} {@($ep)} {}})
# Execute the actual worker's HTTP acceptance function with a mocked transport.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts\background-worker.ps1'),[ref]$tokens,[ref]$errors)
$f=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Send-Webhook'},$true)
. ([scriptblock]::Create($f.Extent.Text))
function Invoke-RestMethod {return [pscustomobject]@{errcode=$script:serverCode}}
$script:serverCode=45009
Check 'http_delivery_without_business_success_rejected' (MustThrow {Send-Webhook 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=fixture' '{}'})
$script:serverCode=0
Check 'business_success_accepted' ((Send-Webhook 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=fixture' '{}').errcode -eq 0)
Check 'unapproved_feedback_endpoint_rejected' (MustThrow {Send-Webhook 'https://evil.invalid/' '{}'})
Write-Output "RESULT failures=0 tests=$count"
