$ErrorActionPreference='Stop'
$source=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../scripts/background-worker.ps1')
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'worker syntax invalid'}
$fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-AdapterTimeoutSummary'},$true)
if(!$fn){throw 'missing production function'}
Invoke-Expression $fn.Extent.Text
function Check($Name,$Valid){if(!$Valid){throw "FAIL $Name"};Write-Output "PASS $Name"}
$now=[datetime]'2026-11-25T13:25:00'
$none=Get-AdapterTimeoutSummary -Now $now -Query {param($f,$limit) if($f.LogName -ne 'System' -or $f.ProviderName -ne 'BTHUSB' -or $f.Id -ne 3 -or $f.StartTime -ne $now.AddHours(-24) -or $f.EndTime -ne $now -or $limit -ne 20){throw 'bad filter'}}
Check 'empty_event_summary_is_explicit' ($none -match 'status=ok count=0 capped=false latestAgeMinutes=none')
$rows=Get-AdapterTimeoutSummary -Now $now -Query {param($f,$limit) [pscustomobject]@{TimeCreated=$now.AddMinutes(-5);Message='SENSITIVE';MachineName='PRIVATE'};[pscustomobject]@{TimeCreated=$now.AddMinutes(-22);Properties='PRIVATE'}}
Check 'count_and_latest_relative_age' ($rows -match 'status=ok count=2 capped=false latestAgeMinutes=5')
Check 'never_outputs_raw_event_fields' ($rows -notmatch 'SENSITIVE|PRIVATE|MachineName|Message|Properties')
$capped=Get-AdapterTimeoutSummary -Now $now -Query {param($f,$limit) 1..20 | ForEach-Object {[pscustomobject]@{TimeCreated=$now.AddMinutes(-$_)}}}
Check 'bounded_limit_is_reported' ($capped -match 'count=20 capped=true latestAgeMinutes=1')
$err=Get-AdapterTimeoutSummary -Now $now -Query {throw 'PRIVATE failure'}
Check 'query_failure_is_not_no_events_and_no_raw_error' ($err -match 'status=unavailable' -and $err -notmatch 'PRIVATE|count=0')
Check 'not_root_cause' ($rows -match 'notRootCause=true')
$issue=$source.Substring($source.IndexOf("'issue' {"),$source.IndexOf("'bluetooth' {")-$source.IndexOf("'issue' {"))
Check 'event_query_only_inside_consented_attachment' ($issue.IndexOf('if ($a.wantFile)') -lt $issue.IndexOf('$adapterSummary=Get-AdapterTimeoutSummary') -and $issue.IndexOf('if ($a.wantFile)') -ge 0)
