param([Parameter(Mandatory)][string]$Request)
$ErrorActionPreference='Stop'
$r=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
$a=$r.args
$result=@{status='fail'}
function Send-Webhook([string]$Url,[string]$Json) {
    if ($Url -notmatch '^https://qyapi\.weixin\.qq\.com/cgi-bin/webhook/send\?key=[a-zA-Z0-9-]+$') { throw 'Invalid feedback endpoint' }
    $response=Invoke-RestMethod -Uri $Url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($Json)) -TimeoutSec 15
    if (!$response.PSObject.Properties['errcode'] -or [int]$response.errcode -ne 0) { throw ('Business response rejected: '+$response.errcode) }
    return $response
}
try {
    switch ($r.kind) {
        {$_ -in 'checkupdate','stageupdate'} {
            Import-Module (Join-Path $PSScriptRoot 'UpdateCore.psm1') -Force
            $release=Get-ApprovedRelease -CurrentVersion $a.version
            if (!$release) { $result.status='current';break }
            $result.version=$release.Version
            if ($r.kind -eq 'checkupdate') { $result.status='available';break }
            # Metadata and digest are fetched again here; no URL from the web page.
            $zip=Join-Path (Split-Path $Request) 'update.zip'
            Invoke-WebRequest -Uri $release.Url -OutFile $zip -TimeoutSec 90 -UseBasicParsing
            $exe=Expand-VerifiedUpdate -Zip $zip -Sha256 $release.Sha256 -Destination (Join-Path (Split-Path $Request) 'unpacked')
            $result.candidate=$exe; $result.hash=(Get-FileHash -LiteralPath $exe).Hash; $result.status='ready'
        }
        'feedback' {
            $null=Send-Webhook $a.webhook ($a.payload | ConvertTo-Json -Compress -Depth 8)
            $result.status='ok'
        }
        'issue' {
            $null=Send-Webhook $a.webhook ($a.payload | ConvertTo-Json -Compress -Depth 8)
            $result.status='ok'
            if ($a.wantFile) {
                try {
                    if (!$a.logPath -or !(Test-Path -LiteralPath $a.logPath -PathType Leaf)) { throw 'No log attachment' }
                    Add-Type -AssemblyName System.Net.Http
                    $client=New-Object Net.Http.HttpClient
                    $client.Timeout=[TimeSpan]::FromSeconds(15)
                    $boundary='----apb'+[guid]::NewGuid().ToString('N')
                    $header='--'+$boundary+"`r`n"+'Content-Disposition: form-data; name="media"; filename="AirPodsBuddy-log.txt"'+"`r`nContent-Type: text/plain`r`n`r`n"
                    $bytes=[Text.Encoding]::UTF8.GetBytes($header)+[IO.File]::ReadAllBytes($a.logPath)+[Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
                    $body=New-Object Net.Http.ByteArrayContent(,$bytes)
                    $body.Headers.TryAddWithoutValidation('Content-Type','multipart/form-data; boundary='+$boundary)|Out-Null
                    try {
                        $response=$client.PostAsync(($a.webhook.Replace('/send?','/upload_media?')+'&type=file'),$body).Result
                        $response.EnsureSuccessStatusCode()|Out-Null
                        $upload=$response.Content.ReadAsStringAsync().Result | ConvertFrom-Json
                        if ($upload.errcode -ne 0 -or !$upload.media_id) { throw 'Attachment upload rejected' }
                        $null=Send-Webhook $a.webhook (@{msgtype='file';file=@{media_id=$upload.media_id}}|ConvertTo-Json -Compress)
                    } finally { $body.Dispose();$client.Dispose() }
                } catch { $result.status='nofile' }
            }
        }
        'bluetooth' {
            if ($a.address -notmatch '^[0-9A-Fa-f]{12}$' -or $a.action -notin 'connect','disconnect') { throw 'Invalid Bluetooth action' }
            Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeBt {
 [DllImport("Bthprops.cpl")] public static extern uint BluetoothGetDeviceInfo(IntPtr radio, IntPtr info);
 [DllImport("Bthprops.cpl")] public static extern uint BluetoothSetServiceState(IntPtr radio,IntPtr info,ref Guid service,uint flags);
}
'@
            $info=[Runtime.InteropServices.Marshal]::AllocHGlobal(560)
            try {
                [Runtime.InteropServices.Marshal]::Copy((New-Object byte[] 560),0,$info,560)
                [Runtime.InteropServices.Marshal]::WriteInt32($info,560)
                [Runtime.InteropServices.Marshal]::WriteInt64($info,8,[Convert]::ToInt64($a.address,16))
                if ([NativeBt]::BluetoothGetDeviceInfo([IntPtr]::Zero,$info) -ne 0) { throw 'Bluetooth device not found' }
                function Set-ServiceState([string]$id,[uint32]$wanted,[int]$attempts=10) {
                    $g=[guid]$id;$state=$wanted
                    for($i=0;$i -lt $attempts;$i++) {
                        $hr=[NativeBt]::BluetoothSetServiceState([IntPtr]::Zero,$info,[ref]$g,$state)
                        if ($hr -eq 0) { if($state -eq $wanted){return 'ok'};$state=1-$state }
                        elseif ($hr -in 87,2147942487) { if($state -eq 0 -and $wanted -eq 0){return 'ok'};$state=1-$state }
                        elseif ($hr -eq 1060 -or ($hr -eq 1168 -and $wanted -eq 0)) { return 'absent' }
                    }
                    return 'fail'
                }
                $hf='{0000111e-0000-1000-8000-00805f9b34fb}';$a2='{0000110b-0000-1000-8000-00805f9b34fb}'
                if ($a.escalateOnly) {
                    $control=Set-ServiceState '{0000110e-0000-1000-8000-00805f9b34fb}' 0 3
                    $ok=$control -in 'ok','absent'
                } elseif ($a.action -eq 'connect') {
                    $null=Set-ServiceState $hf 0 3;$null=Set-ServiceState $a2 0 3;Start-Sleep -Milliseconds 400
                    $h=Set-ServiceState $hf ([uint32][bool]$a.mic);$s=Set-ServiceState $a2 1
                    # A previous disconnect escalation may have disabled AVRCP.
                    # Restore the control service; absence is valid on other headsets.
                    $control=Set-ServiceState '{0000110e-0000-1000-8000-00805f9b34fb}' 1 3
                    $result.control=$control
                    $ok=$s -eq 'ok' -and $h -in 'ok','absent'
                } else {
                    $h=Set-ServiceState $hf 0;$s=Set-ServiceState $a2 0
                    $ok=$h -in 'ok','absent' -and $s -in 'ok','absent'
                }
                if ($ok) {$result.status='ok'} else {$result.status='fail'}
            } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($info) }
        }
        'noise' {
            if ($a.address -notmatch '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' -or $a.mode -notin 'anc','off','trans','adapt') { throw 'Invalid noise request' }
            $noise=Join-Path $PSScriptRoot 'noise_mode.ps1'
            if (!(Test-Path $noise)) {$noise=Join-Path (Split-Path $PSScriptRoot) 'tools\noise_mode.ps1'}
            & $noise -Mac $a.address -Mode $a.mode
            if ($LASTEXITCODE -ne 0) { throw 'Noise helper failed' }
            $result.status='ok'
        }
        default { throw 'Unknown worker task' }
    }
} catch { $result.status='fail';$result.error=$_.Exception.Message.Replace("`r",' ').Replace("`n",' ') }
finally {
    $lines=@($result.GetEnumerator() | ForEach-Object { $_.Key+'='+[string]$_.Value })
    [IO.File]::WriteAllLines($r.result+'.tmp',$lines,(New-Object Text.UTF8Encoding $false))
    [IO.File]::Move($r.result+'.tmp',$r.result)
}
if ($result.status -eq 'fail') {exit 1}
