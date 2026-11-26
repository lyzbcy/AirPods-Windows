$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../scripts/BatteryObservation.psm1') -Force
function Check($Name,$Valid){if(!$Valid){throw "FAIL $Name"};Write-Output "PASS $Name"}
$address='AABBCCDDEEFF'
$node=[pscustomobject]@{InstanceId="BTHENUM\DEV_${address}\PRIVATE";Name='PRIVATE'}
$other=[pscustomobject]@{InstanceId='BTHENUM\DEV_000011112222\OTHER';Name='OTHER'}
$find={ $node; $other }.GetNewClosure()
$container=[guid]'11111111-2222-3333-4444-555555555555'
$cid={param($id)if($id -ne $node.InstanceId){throw 'wrong target'}; $container}.GetNewClosure()
$nodeRead={param($id)if($id -ne $node.InstanceId){throw 'wrong target'}; [byte]33}.GetNewClosure()
$containerRead={param($id)if($id -ne $container){throw 'wrong container'}; [byte]33}.GetNewClosure()
$noValue={param($id) $null}
$missing=Get-OsBatteryObservation -Address $address -FindTarget $find -ReadNode $noValue -ReadContainerId $cid -ReadContainer $noValue
Check 'missing_property_never_fabricates_percent' ($missing.status -eq 'absent' -and $null -eq $missing.percent)
$good=Get-OsBatteryObservation -Address $address -FindTarget $find -ReadNode $nodeRead -ReadContainerId $cid -ReadContainer $containerRead
Check 'exact_observation_keeps_whole_device_scope' ($good.status -eq 'observed' -and $good.percent -eq 33 -and $good.scope -eq 'device_only' -and $good.freshness -eq 'unverified')
$zero=Get-OsBatteryObservation -Address $address -FindTarget $find -ReadNode {[byte]0} -ReadContainerId $cid -ReadContainer $noValue
Check 'zero_percent_is_valid' ($zero.status -eq 'observed' -and $zero.percent -eq 0)
$invalid=Get-OsBatteryObservation -Address $address -FindTarget $find -ReadNode {[byte]255} -ReadContainerId $cid -ReadContainer {'33'}
Check 'out_of_range_or_string_not_displayable' ($invalid.status -eq 'unavailable' -and $invalid.node -eq 'invalid' -and $invalid.container -eq 'invalid' -and $null -eq $invalid.percent)
$conflict=Get-OsBatteryObservation -Address $address -FindTarget $find -ReadNode $nodeRead -ReadContainerId $cid -ReadContainer {[byte]95}
Check 'contradictory_sources_fail_closed' ($conflict.status -eq 'conflicting' -and $null -eq $conflict.percent)
$errorResult=Get-OsBatteryObservation -Address $address -FindTarget $find -ReadNode {throw 'PRIVATE'} -ReadContainerId {[guid]::Empty} -ReadContainer {throw 'forbidden'}
Check 'failure_does_not_disclose_identity_or_exception' (($errorResult|ConvertTo-Json -Compress) -notmatch 'PRIVATE|AABBCCDDEEFF|forbidden' -and $errorResult.status -eq 'unavailable')
$ambig=Get-OsBatteryObservation -Address $address -FindTarget { $node; $node }.GetNewClosure() -ReadNode {throw 'should not read'} -ReadContainerId {throw 'should not read'} -ReadContainer {throw 'should not read'}
Check 'ambiguous_target_does_not_read_properties' ($ambig.status -eq 'target_not_unique' -and $ambig.node -eq 'not_checked' -and $ambig.container -eq 'not_checked')
$bad=Get-OsBatteryObservation -Address 'not-an-address' -FindTarget {throw 'should not enumerate'}
Check 'invalid_target_does_not_enumerate' ($bad.status -eq 'invalid_target')
