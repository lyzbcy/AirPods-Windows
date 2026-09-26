$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Import-Module (Join-Path $root 'scripts\KsBluetooth.psm1') -Force
$a='70AE2AA42B80';$c='11111111-1111-1111-1111-111111111111';$count=0
function Check([string]$name,[bool]$ok){if(!$ok){throw "FAIL $name"};$script:count++;"PASS $name"}
$global:rows=@();$global:pollRows=@();$global:enableCalls=0;$global:enabledAddress='';$global:hr=[uint32]0
$list={param($container)
 if($container -ne $c){throw 'wrong container'}
 if($global:enableCalls -gt 0){return $global:pollRows}
 return $global:rows
}.GetNewClosure()
$enable={param($address)$global:enableCalls++;$global:enabledAddress=$address;return $global:hr}
function Row([int]$flow,[int]$state,[string]$filter=''){
 return [pscustomobject]@{Flow=$flow;State=$state;FilterId=$filter}
}
$global:rows=@((Row 1 8));$global:enableCalls=0
$r=Restore-LegacyHfp -Address $a -Container $c -List $list -Enable $enable -PollMilliseconds 0 -MaxChecks 2
Check 'existing_capture_does_not_install_driver' ($r -eq 'present' -and $global:enableCalls -eq 0)
$global:rows=@((Row 1 2));$global:enableCalls=0
$r=Restore-LegacyHfp -Address $a -Container $c -List $list -Enable $enable -PollMilliseconds 0 -MaxChecks 2
Check 'user_disabled_capture_not_overridden' ($r -eq 'disabled' -and $global:enableCalls -eq 0)
$global:rows=@((Row 0 8 'BTHHFENUM'));$global:enableCalls=0
$r=Restore-LegacyHfp -Address $a -Container $c -List $list -Enable $enable -PollMilliseconds 0 -MaxChecks 2
Check 'hfp_filter_without_capture_not_reinstalled' ($r -eq 'hfp-present-capture-missing' -and $global:enableCalls -eq 0)
$global:rows=@((Row 0 8 'BTHA2DP'));$global:pollRows=@((Row 1 8));$global:enableCalls=0;$global:hr=[uint32]0
$r=Restore-LegacyHfp -Address $a -Container $c -List $list -Enable $enable -PollMilliseconds 0 -MaxChecks 2
Check 'missing_capture_one_exact_hfp_enable_then_readback' ($r -eq 'restored' -and $global:enableCalls -eq 1 -and $global:enabledAddress -eq $a)
$global:rows=@((Row 0 8 'BTHA2DP'));$global:pollRows=@((Row 1 1));$global:enableCalls=0;$global:hr=[uint32]2147942487
$r=Restore-LegacyHfp -Address $a -Container $c -List $list -Enable $enable -PollMilliseconds 0 -MaxChecks 2
Check 'already_enabled_still_requires_capture_readback' ($r -eq 'already-enabled' -and $global:enableCalls -eq 1)
$global:rows=@((Row 0 8 'BTHA2DP'));$global:enableCalls=0;$global:hr=[uint32]1060
$r=Restore-LegacyHfp -Address $a -Container $c -List $list -Enable $enable -PollMilliseconds 0 -MaxChecks 2
Check 'unsupported_hfp_reports_without_retry' ($r -eq 'failed:0x00000424' -and $global:enableCalls -eq 1)
$global:rows=@((Row 0 8 'BTHA2DP'));$global:pollRows=@();$global:enableCalls=0;$global:hr=[uint32]0
$r=Restore-LegacyHfp -Address $a -Container $c -List $list -Enable $enable -PollMilliseconds 0 -MaxChecks 2
Check 'late_capture_timeout_stops_after_one_enable' ($r -eq 'unavailable' -and $global:enableCalls -eq 1)
$global:enableCalls=0
try{Restore-LegacyHfp -Address 'wildcard' -Container $c -List $list -Enable $enable|Out-Null;throw 'did not reject'}catch{if($_.Exception.Message -eq 'did not reject'){throw}}
Check 'invalid_address_rejected_before_enable' ($global:enableCalls -eq 0)
Initialize-KsBluetooth
Check 'invalid_native_address_no_service_call' ([AirPodsBuddy.Ks.BluetoothLink]::EnableTargetHfp('wildcard') -eq 87)
$global:capRows=@();$global:capReads=0;$global:sendCalls=0;$global:sendId=''
$capList={param($container)
 $global:capReads++
 return $global:capRows[[Math]::Min($global:capReads-1,$global:capRows.Count-1)]
}
$send={param($id,$property)$global:sendCalls++;$global:sendId=$id;return 0}
$active=[pscustomobject]@{Flow=1;State=1;Id='capture';ReconnectSupported=$true}
$unplugged=[pscustomobject]@{Flow=1;State=8;Id='capture';ReconnectSupported=$true}
$global:capRows=@(@($active));$global:capReads=0;$global:sendCalls=0
$r=Wait-CaptureAfterRestore -Container $c -List $capList -Send $send -PollMilliseconds 0 -MaxChecks 2
Check 'late_active_capture_readback_needs_no_new_request' ($r.status -eq 'active' -and $r.id -eq 'capture' -and $global:sendCalls -eq 0)
$global:capRows=@(@($unplugged),@($active));$global:capReads=0;$global:sendCalls=0
$r=Wait-CaptureAfterRestore -Container $c -List $capList -Send $send -PollMilliseconds 0 -MaxChecks 2
Check 'late_unplugged_capture_one_target_request_then_active' ($r.status -eq 'active' -and $global:sendCalls -eq 1 -and $global:sendId -eq 'capture' -and $r.trace -match '0,capture,0x00000000$')
$global:capRows=@(@($unplugged),@($unplugged));$global:capReads=0;$global:sendCalls=0
$r=Wait-CaptureAfterRestore -Container $c -List $capList -Send $send -AlreadyRequested $true -PollMilliseconds 0 -MaxChecks 2
Check 'previous_policy_request_never_duplicated' ($r.status -eq 'unavailable' -and $global:sendCalls -eq 0)
$disabled=[pscustomobject]@{Flow=1;State=2;Id='capture';ReconnectSupported=$false}
$global:capRows=@(@($disabled));$global:capReads=0;$global:sendCalls=0
$r=Wait-CaptureAfterRestore -Container $c -List $capList -Send $send -PollMilliseconds 0 -MaxChecks 1
Check 'late_user_disabled_capture_not_enabled' ($r.status -eq 'disabled' -and $global:sendCalls -eq 0)
'RESULT failures=0 tests='+$count
