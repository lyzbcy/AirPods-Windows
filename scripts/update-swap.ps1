param([Parameter(Mandatory)][string]$Request)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateCore.psm1') -Force
$r=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
$receipt=Join-Path $r.directory 'update_result.txt'
$child=$null
$old=$null
$healthFile=$null
$originalHash=(Get-FileHash -LiteralPath (Join-Path $r.directory 'AirPodsBuddy.exe')).Hash
try {
    $old=Get-Process -Id $r.oldPid -ErrorAction SilentlyContinue
    if ($old -and !$old.WaitForExit(30000)) { throw 'Old application did not exit' }
    $healthFile=Join-Path $r.directory ('update-health-'+$r.token+'.ready')
    $check={
        param($exe)
        $script:child=Start-Process -FilePath $exe -ArgumentList @('/update-health',$r.token) -WindowStyle Hidden -PassThru
        $deadline=(Get-Date).AddSeconds(40)
        while((Get-Date) -lt $deadline -and !$script:child.HasExited) {
            if (Test-Path -LiteralPath $healthFile) {
                if ((Get-Content -LiteralPath $healthFile -Raw).Trim() -eq $r.version) {
                    Start-Sleep -Seconds 3
                    if (!$script:child.HasExited -and (Get-Content -LiteralPath $healthFile -Raw).Trim() -eq $r.version) {return $true}
                }
                break
            }
            Start-Sleep -Milliseconds 250
        }
        if (!$script:child.HasExited) { $script:child.Kill(); $script:child.WaitForExit(5000) | Out-Null }
        return $false
    }
    $result=Invoke-UpdateTransaction -Candidate $r.candidate -Destination (Join-Path $r.directory 'AirPodsBuddy.exe') -ExpectedHash $r.hash -HealthCheck $check
    [IO.File]::WriteAllText($receipt,'ok')
} catch {
    [IO.File]::WriteAllText($receipt,'fail '+$_.Exception.Message)
    if ((!$old -or $old.HasExited) -and (Get-FileHash -LiteralPath (Join-Path $r.directory 'AirPodsBuddy.exe')).Hash -eq $originalHash) {
        Start-Process -FilePath (Join-Path $r.directory 'AirPodsBuddy.exe') -WindowStyle Hidden
    }
    exit 1
} finally {
    if ($healthFile -and (Test-Path -LiteralPath $healthFile)) { Remove-Item -LiteralPath $healthFile -Force }
}
