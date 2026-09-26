param([Parameter(Mandatory)][string]$Request)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateCore.psm1') -Force
$r=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
$receipt=Join-Path $r.directory 'update_result.txt'
$child=$null
$old=$null
$healthFile=$null
$originalHash=(Get-FileHash -LiteralPath (Join-Path $r.directory 'AirPodsBuddy.exe')).Hash

function Invoke-UpdateFailureRecovery {
    param([string]$Directory,[string]$OriginalHash,[object]$OldProcess,
          [string]$Receipt,[string]$Message,
          [scriptblock]$WriteReceipt = {param($path,$text) [IO.File]::WriteAllText($path,$text)},
          [scriptblock]$StartApp = {param($exe) Start-Process -FilePath $exe -WindowStyle Hidden | Out-Null})
    try { & $WriteReceipt $Receipt ('fail '+$Message) }
    catch { Write-Warning ('Update receipt write failed: '+$_.Exception.Message) }
    $exe=Join-Path $Directory 'AirPodsBuddy.exe'
    if ((!$OldProcess -or $OldProcess.HasExited) -and
        (Get-FileHash -LiteralPath $exe).Hash -eq $OriginalHash) {
        & $StartApp $exe
    }
}
try {
    $old=Get-Process -Id $r.oldPid -ErrorAction SilentlyContinue
    if ($old -and !$old.WaitForExit(30000)) { throw 'Old application did not exit' }
    $healthFile=Join-Path $r.directory ('update-health-'+$r.token+'.ready')
    $check={
        param($exe)
        $script:child=Start-Process -FilePath $exe -ArgumentList @('/update-health',$r.token) -WindowStyle Hidden -PassThru
        $healthy=$false
        $deadline=(Get-Date).AddSeconds(40)
        try {
            while((Get-Date) -lt $deadline -and !$script:child.HasExited) {
                if (Test-Path -LiteralPath $healthFile) {
                    if ((Get-Content -LiteralPath $healthFile -Raw).Trim() -eq $r.version) {
                        Start-Sleep -Seconds 3
                        if (!$script:child.HasExited -and (Get-Content -LiteralPath $healthFile -Raw).Trim() -eq $r.version) {
                            $healthy=$true
                            return $true
                        }
                    }
                    break
                }
                Start-Sleep -Milliseconds 250
            }
            return $false
        } finally {
            if (!$healthy -and $script:child -and !$script:child.HasExited) {
                $script:child.Kill()
                $script:child.WaitForExit(5000) | Out-Null
            }
        }
    }
    $result=Invoke-UpdateTransaction -Candidate $r.candidate -Destination (Join-Path $r.directory 'AirPodsBuddy.exe') -ExpectedHash $r.hash -HealthCheck $check
    [IO.File]::WriteAllText($receipt,'ok')
} catch {
    Invoke-UpdateFailureRecovery -Directory $r.directory -OriginalHash $originalHash -OldProcess $old -Receipt $receipt -Message $_.Exception.Message
    exit 1
} finally {
    if ($healthFile -and (Test-Path -LiteralPath $healthFile)) { Remove-Item -LiteralPath $healthFile -Force }
}
