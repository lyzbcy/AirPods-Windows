[CmdletBinding()]
param([switch]$Repair,[string]$InstanceId,[string]$EndpointId,[string]$OutputDirectory=(Join-Path $PSScriptRoot 'logs'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts\RepairCore.psm1') -Force
$receipt=[ordered]@{time=(Get-Date).ToString('o');mode='diagnostic';status='not_started';audible='not_tested';before=@();after=@();error=''}
$exitCode=1
try {
    $receipt.before=@(Get-ActiveRenderEndpoints)
    if (!$Repair) {
        $receipt.after=$receipt.before;$receipt.status='diagnostic_complete';$exitCode=0
    } else {
        $receipt.mode='targeted_repair'
        if (!$InstanceId -or !$EndpointId) { throw 'Use -Repair with an exact -InstanceId and -EndpointId from diagnostics' }
        $device=Get-PnpDevice -InstanceId $InstanceId -ErrorAction Stop
        if ($device.Class -ne 'MEDIA' -or $device.Status -ne 'OK') { throw 'Only an initially enabled MEDIA node may be restarted' }
        $ok=Invoke-TargetedRepair -InstanceId $InstanceId -EndpointId $EndpointId -Disable {param($id) Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop} -Enable {param($id) Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop} -Probe {Get-ActiveRenderEndpoints} -Wait {Start-Sleep -Seconds 2}
        $receipt.after=@(Get-ActiveRenderEndpoints)
        if ($ok) {$receipt.status='target_render_active';$exitCode=0} else {$receipt.status='target_render_missing';$exitCode=2}
    }
} catch {$receipt.status='failed';$receipt.error=$_.Exception.Message;$exitCode=1}
finally {
    try {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        $path=Join-Path $OutputDirectory ('audio-repair-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$PID+'.json')
        $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
        Write-Output ('RECEIPT='+$path)
        Write-Output ('STATUS='+$receipt.status+'; AUDIBLE=not_tested')
    } catch {Write-Error 'Diagnostic receipt could not be persisted' -ErrorAction Continue;$exitCode=3}
}
exit $exitCode
