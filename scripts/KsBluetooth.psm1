Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Initialize-KsBluetooth {
 if(!('AirPodsBuddy.Ks.NativeBackend' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'KsBluetooth.cs')}
}
function Resolve-BluetoothContainer {
 param([string]$Address,[scriptblock]$Find,[scriptblock]$ReadContainer)
 if($Address -notmatch '^[0-9A-Fa-f]{12}$'){throw 'Invalid Bluetooth address'}
 if(!$Find){$Find={Get-PnpDevice -Class Bluetooth -ErrorAction Stop}}
 if(!$ReadContainer){$ReadContainer={param($id)(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_ContainerId -ErrorAction Stop).Data}}
 $nodes=@(& $Find | Where-Object {$_.InstanceId -match ('(?i)^BTHENUM\\DEV_'+$Address+'\\')})
 if($nodes.Count -ne 1){throw 'Exact paired Bluetooth node not uniquely found'}
 $id=[guid](& $ReadContainer $nodes[0].InstanceId)
 if($id -eq [guid]::Empty){throw 'Bluetooth container is empty'}
 return $id.ToString('D')
}
function Get-KsBluetoothProbe {
 param([string]$Address)
 Initialize-KsBluetooth
 $container=Resolve-BluetoothContainer $Address
 $api=New-Object AirPodsBuddy.Ks.NativeBackend
 return [pscustomobject]@{address=$Address;container=$container;endpoints=@($api.List($container));operation='read_only_support_probe'}
}
function Restore-LegacyHfp {
 param([string]$Address,[string]$Container,[scriptblock]$List,[scriptblock]$Enable,[int]$PollMilliseconds=500,[int]$MaxChecks=8)
 if($Address -notmatch '^[0-9A-Fa-f]{12}$'){throw 'Invalid exact microphone migration target'}
 try {$id=[guid]$Container} catch {throw 'Invalid exact microphone migration target'}
 if($id -eq [guid]::Empty){throw 'Invalid exact microphone migration target'}
 if(!$List){Initialize-KsBluetooth;$api=New-Object AirPodsBuddy.Ks.NativeBackend;$List={param($c)$api.List($c)}.GetNewClosure()}
 if(!$Enable){Initialize-KsBluetooth;$Enable={param($a)[AirPodsBuddy.Ks.BluetoothLink]::EnableTargetHfp($a)}}
 $rows=@(& $List $Container)
 $capture=@($rows | Where-Object {$_.Flow -eq 1})
 if(@($capture | Where-Object {$_.State -eq 2}).Count){return 'disabled'}
 if(@($capture | Where-Object {$_.State -in 1,8}).Count){return 'present'}
 if(@($rows | Where-Object {$_.FilterId -match '(?i)BTHHFENUM|0000111E'}).Count){return 'hfp-present-capture-missing'}
 $hr=[uint32](& $Enable $Address)
 if($hr -ne 0 -and $hr -ne [uint32]2147942487){return ('failed:0x{0:X8}' -f $hr)}
 for($i=0;$i -lt $MaxChecks;$i++) {
  if($PollMilliseconds -gt 0){Start-Sleep -Milliseconds $PollMilliseconds}
  $capture=@(& $List $Container | Where-Object {$_.Flow -eq 1})
  if(@($capture | Where-Object {$_.State -eq 2}).Count){return 'disabled'}
  if(@($capture | Where-Object {$_.State -in 1,8}).Count){return $(if($hr -eq 0){'restored'}else{'already-enabled'})}
 }
 return 'unavailable'
}
function Wait-CaptureAfterRestore {
 param([string]$Container,[scriptblock]$List,[scriptblock]$Send,[bool]$AlreadyRequested=$false,[int]$PollMilliseconds=500,[int]$MaxChecks=12)
 if(!$List -or !$Send){throw 'Capture verification callbacks required'}
 $requested=$AlreadyRequested;$trace=''
 for($i=0;$i -lt $MaxChecks;$i++) {
  if($i -gt 0 -and $PollMilliseconds -gt 0){Start-Sleep -Milliseconds $PollMilliseconds}
  try {$rows=@(& $List $Container)} catch {continue}
  $caps=@($rows | Where-Object {$_.Flow -eq 1 -and $_.State -in 1,8})
  if(@($rows | Where-Object {$_.Flow -eq 1 -and $_.State -eq 2}).Count){return @{status='disabled';id='';requested=[int]$requested;trace=$trace}}
  if($caps.Count -gt 1){return @{status='ambiguous';id='';requested=[int]$requested;trace=$trace}}
  if($caps.Count -eq 1) {
   $ep=$caps[0]
   if($ep.State -eq 1){return @{status='active';id=$ep.Id;requested=[int]$requested;trace=$trace}}
   if(!$requested) {
    if(!$ep.ReconnectSupported){return @{status='unsupported';id='';requested=0;trace=$trace}}
    $before=[DateTime]::UtcNow.ToFileTimeUtc()
    try {$hr=[int](& $Send $ep.Id 0)} catch {$hr=[int]$_.Exception.HResult}
    $after=[DateTime]::UtcNow.ToFileTimeUtc()
    $trace="$before,$after,0,$($ep.Id),0x$($hr.ToString('X8'))"
    $requested=$true
    if($hr -lt 0){return @{status='request-failed';id='';requested=1;trace=$trace}}
   }
  }
 }
 return @{status='unavailable';id='';requested=[int]$requested;trace=$trace}
}
function Invoke-KsBluetooth {
 param([string]$Address,[ValidateSet('connect','disconnect')][string]$Action,[bool]$Microphone=$false,[bool]$MicRestore=$false)
 Initialize-KsBluetooth
 $container=Resolve-BluetoothContainer $Address
 $repair='not-requested'
 if($Action -eq 'connect' -and $Microphone -and $MicRestore){$repair=Restore-LegacyHfp -Address $Address -Container $container}
 $api=New-Object AirPodsBuddy.Ks.NativeBackend
 $linkState=[AirPodsBuddy.Ks.BluetoothLink]::Read($Address)
 $r=[AirPodsBuddy.Ks.Policy]::Run($api,$container,($Action -eq 'connect'),$Microphone,$linkState)
 if($MicRestore -and $Microphone -and $Action -eq 'connect' -and $r.Accepted -and $repair -in 'restored','already-enabled') {
  $list={param($c)$api.List($c)}.GetNewClosure()
  $send={param($id,$property)$api.Send($id,[uint32]$property)}.GetNewClosure()
  $capture=Wait-CaptureAfterRestore -Container $container -List $list -Send $send -AlreadyRequested ($r.CaptureId -ne '')
  if($capture.trace){$r.KsTrace+=$(if($r.KsTrace){';'}else{''})+$capture.trace}
  if($capture.requested -and $r.CaptureId -eq ''){$r.Requested++}
  if($capture.status -eq 'active'){$r.CaptureId=$capture.id}
  else {$r.CaptureId='';$repair='capture-'+$capture.status}
 }
 return @{status=$(if($r.Accepted){'ok'}else{'fail'});backend='ks';container=$container;linkState=$linkState;renderId=$r.RenderId;captureId=$r.CaptureId;requested=$r.Requested;error=$r.Error;ksTrace=$r.KsTrace;targetEndpoints=$r.TargetEndpoints;micRepair=$repair}
}
Export-ModuleMember -Function Initialize-KsBluetooth,Resolve-BluetoothContainer,Get-KsBluetoothProbe,Restore-LegacyHfp,Wait-CaptureAfterRestore,Invoke-KsBluetooth
