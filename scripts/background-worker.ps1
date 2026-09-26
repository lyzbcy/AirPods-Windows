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
            Import-Module (Join-Path $PSScriptRoot 'KsBluetooth.psm1') -Force
            $ks=Invoke-KsBluetooth -Address ([string]$a.address) -Action ([string]$a.action) -Microphone ([bool]$a.mic)
            foreach($key in $ks.Keys){if($null -ne $ks[$key]){$result[$key]=$ks[$key]}}
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
