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
function Invoke-KsBluetooth {
 param([string]$Address,[ValidateSet('connect','disconnect')][string]$Action,[bool]$Microphone=$false)
 Initialize-KsBluetooth
 $container=Resolve-BluetoothContainer $Address
 $api=New-Object AirPodsBuddy.Ks.NativeBackend
 $r=[AirPodsBuddy.Ks.Policy]::Run($api,$container,($Action -eq 'connect'),$Microphone)
 return @{status=$(if($r.Accepted){'ok'}else{'fail'});backend='ks';container=$container;renderId=$r.RenderId;captureId=$r.CaptureId;requested=$r.Requested;error=$r.Error}
}
Export-ModuleMember -Function Initialize-KsBluetooth,Resolve-BluetoothContainer,Get-KsBluetoothProbe,Invoke-KsBluetooth
