$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$source=Get-Content (Join-Path $root 'scripts\KsBluetooth.cs') -Raw -Encoding UTF8
$fake=@'
namespace AirPodsBuddy.Ks {
 public sealed class FakeBackend : IBackend {
  public Endpoint[] Rows; public System.Collections.Generic.List<string> Calls=new System.Collections.Generic.List<string>();
  public int FailAt=0;
  public int ThrowAt=0;
  public Endpoint[] List(string container){return Rows;}
  public int Send(string id,uint property){Calls.Add(id+":"+property);if(ThrowAt==Calls.Count)throw new System.Runtime.InteropServices.COMException("driver",unchecked((int)0x80004002));return FailAt==Calls.Count?unchecked((int)0x80004005):0;}
 }
}
'@
Add-Type -TypeDefinition ($source+"`n"+$fake)
Import-Module (Join-Path $root 'scripts\KsBluetooth.psm1') -Force
$count=0
function Check([string]$Name,[bool]$Ok){if(!$Ok){throw "FAIL $Name"};$script:count++;"PASS $Name"}
function MustThrow([scriptblock]$Code){try{&$Code|Out-Null;return $false}catch{return $true}}
$a='11111111-1111-1111-1111-111111111111';$b='22222222-2222-2222-2222-222222222222'
function Ep([string]$Id,[int]$Flow,[uint32]$State,[string]$Container=$a,[string]$Filter=''){
 $e=New-Object AirPodsBuddy.Ks.Endpoint;$e.Id=$Id;$e.Name='Same name';$e.ContainerId=$Container;$e.Flow=$Flow;$e.State=$State;$e.FilterId=$(if($Filter){$Filter}else{'filter-'+$Id});$e.ReconnectSupported=$true;$e.DisconnectSupported=$true;return $e
}
function Fake($Rows){$f=New-Object AirPodsBuddy.Ks.FakeBackend;$f.Rows=[AirPodsBuddy.Ks.Endpoint[]]$Rows;return $f}
$f=Fake @((Ep 'render' 0 1),(Ep 'capture' 1 8));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)
Check 'already_active_render_is_not_disconnected_or_reconnected' ($r.Accepted -and $f.Calls.Count -eq 0 -and $r.RenderId -eq 'render')
$f=Fake @((Ep 'render' 0 8),(Ep 'other' 0 8 $b));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)
Check 'unplugged_exact_container_single_connect_request' ($r.Accepted -and $f.Calls.Count -eq 1 -and $f.Calls[0] -eq 'render:0')
Check 'ks_trace_records_exact_request_and_hresult' ($r.KsTrace -match '^\d+,\d+,0,render,0x00000000$')
Check 'same_name_other_container_untouched' ($f.Calls -notcontains 'other:0')
$f=Fake @((Ep 'render' 0 8),(Ep 'capture' 1 8));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)
Check 'mic_off_leaves_capture_service_untouched' ($r.Accepted -and $f.Calls.Count -eq 1)
$f=Fake @((Ep 'render' 0 8),(Ep 'capture' 1 8));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$true)
Check 'mic_on_includes_target_capture' ($r.Accepted -and $f.Calls.Count -eq 2 -and $r.CaptureId -eq 'capture')
$f=Fake @((Ep 'render' 0 1),(Ep 'capture' 1 1),(Ep 'other' 1 1 $b));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$false,$false)
Check 'disconnect_covers_render_and_capture_only_target' ($r.Accepted -and $f.Calls.Count -eq 2 -and $f.Calls[0] -eq 'render:1' -and $f.Calls[1] -eq 'capture:1')
Check 'disconnect_returns_exact_target_endpoint_ids' ($r.TargetEndpoints -eq '0|render;1|capture' -and $r.TargetEndpoints -notmatch 'other')
$f=Fake @((Ep 'render' 0 8),(Ep 'capture' 1 8));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$false,$false)
Check 'unplugged_audio_still_requests_control_link_disconnect' ($r.Accepted -and $r.Requested -eq 2 -and $f.Calls[0] -eq 'render:1' -and $f.Calls[1] -eq 'capture:1')
$f=Fake @((Ep 'render' 0 1 $a 'shared'),(Ep 'capture' 1 1 $a 'shared'));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$false,$false)
Check 'shared_ks_filter_requested_only_once' ($r.Accepted -and $f.Calls.Count -eq 1)
$f=Fake @((Ep 'render' 0 1),(Ep 'capture' 1 1));$f.Rows[1].DisconnectSupported=$false;$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$false,$false)
Check 'unsupported_capture_aborts_before_any_disconnect' (!$r.Accepted -and $f.Calls.Count -eq 0)
$f=Fake @((Ep 'render' 0 8));$f.Rows[0].ReconnectSupported=$false;$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)
Check 'unsupported_connect_does_not_toggle_services' (!$r.Accepted -and $f.Calls.Count -eq 0)
$f=Fake @((Ep 'render' 0 2));Check 'user_disabled_endpoint_not_enabled' (MustThrow {[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)})
$f=Fake @((Ep 'render' 0 4));Check 'notpresent_endpoint_not_connected' (MustThrow {[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)})
$f=Fake @((Ep 'r1' 0 8),(Ep 'r2' 0 8));Check 'ambiguous_stereo_endpoints_fail_closed' (MustThrow {[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)})
$f=Fake @((Ep 'r' 0 8),(Ep 'hfp' 0 8 $a 'BTHHFENUM'));$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)
Check 'known_hfp_render_not_selected_as_stereo' ($r.Accepted -and $r.RenderId -eq 'r' -and $f.Calls.Count -eq 1)
$f=Fake @((Ep 'r' 0 8),(Ep 'capture' 1 8));$f.FailAt=1;$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$true)
Check 'driver_error_not_accepted_and_no_blind_retry' (!$r.Accepted -and $r.Requested -eq 1 -and $f.Calls.Count -eq 1 -and $r.Error -match '80004005')
Check 'ks_trace_records_driver_failure_hresult' ($r.KsTrace -match '^\d+,\d+,0,r,0x80004005$')
$f=Fake @((Ep 'r' 0 8));$f.ThrowAt=1;$r=[AirPodsBuddy.Ks.Policy]::Run($f,$a,$true,$false)
Check 'ks_trace_records_exception_hresult_without_retry' (!$r.Accepted -and $r.Requested -eq 1 -and $f.Calls.Count -eq 1 -and $r.KsTrace -match '^\d+,\d+,0,r,0x80004002$')
Check 'empty_container_rejected' (MustThrow {[AirPodsBuddy.Ks.Policy]::Run($f,[guid]::Empty.ToString(),$true,$false)})
Check 'invalid_address_rejected_before_discovery' (MustThrow {Resolve-BluetoothContainer 'name or wildcard' {throw 'should not run'} {}})
$nodes=@([pscustomobject]@{InstanceId='BTHENUM\DEV_AABBCCDDEEFF\ONE'},[pscustomobject]@{InstanceId='BTHENUM\DEV_AABBCCDDEEF0\OTHER'})
$c=Resolve-BluetoothContainer 'aabbccddeeff' {$nodes} {param($id) if($id -notlike '*EEFF\ONE'){throw 'wrong device'};return $a}
Check 'address_resolves_exact_pnp_container_not_friendly_name' ($c -eq $a)
Check 'duplicate_physical_nodes_rejected' (MustThrow {Resolve-BluetoothContainer 'AABBCCDDEEFF' {@($nodes[0],$nodes[0])} {$a}})
Check 'empty_pnp_container_rejected' (MustThrow {Resolve-BluetoothContainer 'AABBCCDDEEFF' {$nodes} {[guid]::Empty}})
'RESULT failures=0 tests='+$count
