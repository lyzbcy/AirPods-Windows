# Independent, one-shot OS metadata observation; no BLE or GATT requests.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:BatteryKey = '{49CD1F76-5626-4B17-A4E8-18B4AA1A2213} 10'

function Read-ContainerBatteryProperty {
    param([guid]$Container)
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $type = [Windows.Devices.Enumeration.DeviceInformation,Windows.Devices.Enumeration,ContentType=WindowsRuntime]
    $kind = [Windows.Devices.Enumeration.DeviceInformationKind,Windows.Devices.Enumeration,ContentType=WindowsRuntime]::DeviceContainer
    $asTask = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1
    })[0]
    $operation = $type::CreateFromIdAsync($Container.ToString('B'),[string[]]@('System.Devices.BatteryLife'),$kind)
    $task = $asTask.MakeGenericMethod($type).Invoke($null,@($operation))
    if(!$task.Wait(5000)) { throw 'container property timeout' }
    $info = $task.Result
    if($null -eq $info) { throw 'container unavailable' }
    # The projected WinRT property bag returns null for missing properties.
    # StrictMode treats an absent dynamic dictionary key as a lookup error.
    Set-StrictMode -Off
    return $info.Properties['System.Devices.BatteryLife']
}

function Convert-BatteryProperty {
    param($Value)
    if($null -eq $Value) { return @{status='absent';percent=$null} }
    if($Value -isnot [byte] -or $Value -gt 100) { return @{status='invalid';percent=$null} }
    return @{status='observed';percent=[int]$Value}
}

function Get-OsBatteryObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [scriptblock]$FindTarget,
        [scriptblock]$ReadNode,
        [scriptblock]$ReadContainerId,
        [scriptblock]$ReadContainer
    )
    # Do not emit address, names, instance IDs, raw property data or exception text.
    $result = [ordered]@{status='unavailable';node='not_checked';container='not_checked';percent=$null;scope='device_only';freshness='unverified'}
    if($Address -notmatch '^[0-9A-Fa-f]{12}$') {
        $result.status='invalid_target';return [pscustomobject]$result
    }
    if(!$FindTarget) { $FindTarget={Get-PnpDevice -Class Bluetooth -ErrorAction Stop} }
    if(!$ReadNode) {
        $ReadNode={param($id)
            $rows=@(Get-PnpDeviceProperty -InstanceId $id -KeyName $script:BatteryKey -ErrorAction Stop)
            if($rows.Count -ne 1){throw 'battery property not unique'}
            if($rows[0].Type -eq 'Empty' -or !$rows[0].PSObject.Properties['Data']) { return $null }
            return $rows[0].Data
        }
    }
    if(!$ReadContainerId) { $ReadContainerId={param($id)(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_ContainerId -ErrorAction Stop).Data} }
    if(!$ReadContainer) { $ReadContainer={param($id)Read-ContainerBatteryProperty $id} }
    try {
        $nodes=@(& $FindTarget | Where-Object {$_.InstanceId -match ('(?i)^BTHENUM\\DEV_'+$Address+'\\')})
    } catch { return [pscustomobject]$result }
    if($nodes.Count -ne 1) {
        $result.status='target_not_unique';return [pscustomobject]$result
    }
    $nodeId=$nodes[0].InstanceId
    try { $a=Convert-BatteryProperty (& $ReadNode $nodeId) } catch { $a=@{status='unavailable';percent=$null} }
    try {
        $containerId=[guid](& $ReadContainerId $nodeId)
        if($containerId -eq [guid]::Empty){throw 'empty container'}
        $b=Convert-BatteryProperty (& $ReadContainer $containerId)
    } catch { $b=@{status='unavailable';percent=$null} }
    $result.node=$a.status;$result.container=$b.status
    $values=@(@($a,$b) | Where-Object {$_.status -eq 'observed'} | ForEach-Object {$_.percent})
    if($values.Count -eq 2 -and $values[0] -ne $values[1]) {
        $result.status='conflicting'
    } elseif($values.Count -gt 0) {
        $result.status='observed';$result.percent=$values[0]
    } elseif($a.status -eq 'absent' -and $b.status -eq 'absent') {
        $result.status='absent'
    }
    return [pscustomobject]$result
}
Export-ModuleMember -Function Get-OsBatteryObservation
