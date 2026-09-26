[CmdletBinding()]
param([switch]$Deploy,[string]$Destination=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'AirPodsBuddy'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Push-Location $root
try {
    & (Join-Path $root 'webui\build_ui.ps1')
    $compiler=Join-Path $root 'tools\ahk2exe_stable\Ahk2Exe.exe'
    $base=Join-Path $root 'tools\ahk_v2_portable\AutoHotkey64.exe'
    if (!(Test-Path $compiler) -or !(Test-Path $base)) {throw 'Build tools missing; installed application untouched'}
    # Snapshot every source/embedded resource/tool consumed by Ahk2Exe after
    # the UI build. Do not deploy an exe assembled from drifting inputs.
    $inputPaths=@('airpods_buddy.ahk','webui\index.html','webui\index_built.html',
        'webui\pet.html','webui\pet_built.html','webui\build_ui.ps1','tools\noise_mode.ps1',
        'tools\ahk2exe_stable\Ahk2Exe.exe','tools\ahk_v2_portable\AutoHotkey64.exe',
        'scripts\background-worker.ps1','scripts\UpdateCore.psm1','scripts\update-swap.ps1')
    $inputPaths+=@(Get-ChildItem (Join-Path $root 'lib') -Recurse -File |
        Where-Object {$_.Extension -in '.ahk','.dll'} |
        ForEach-Object {$_.FullName.Substring($root.Length+1)})
    $inputPaths+=@(Get-ChildItem (Join-Path $root 'assets') -File -Filter '*.ico' |
        ForEach-Object {$_.FullName.Substring($root.Length+1)})
    $inputPaths+=@(Get-ChildItem (Join-Path $root 'webui\assets') -File |
        ForEach-Object {$_.FullName.Substring($root.Length+1)})
    $inputs=[ordered]@{}
    foreach($relative in ($inputPaths | Sort-Object -Unique)) {
        $file=Join-Path $root $relative
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) {throw "Build input missing: $relative"}
        $inputs[$relative.Replace('\','/')]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    $build=Join-Path $root ('dist\build-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $build -Force | Out-Null
    $candidate=Join-Path $build 'AirPodsBuddy.exe'
    $arguments='/silent /compress 0 /in "'+(Join-Path $root 'airpods_buddy.ahk')+'" /out "'+$candidate+'" /base "'+$base+'" /icon "'+(Join-Path $root 'assets\star_pudding.ico')+'"'
    $process=Start-Process -FilePath $compiler -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru
    if (!$process.WaitForExit(60000)) {$process.Kill();throw 'Compiler timed out; installed application untouched'}
    if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $candidate)) {throw 'Compile failed; installed application untouched'}
    foreach($relative in $inputs.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash -ne $inputs[$relative]) {
            throw "Build input changed during compilation: $relative"
        }
    }
    $hash=(Get-FileHash -LiteralPath $candidate).Hash
    $version=[regex]::Match((Get-Content airpods_buddy.ahk -Raw),'APP_VERSION\s*:=\s*"([^"]+)"').Groups[1].Value
    @{version=$version;sha256=$hash;source=$inputs['airpods_buddy.ahk'];inputs=$inputs;builtAt=(Get-Date).ToString('o')}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $build 'build-manifest.json') -Encoding UTF8
    Write-Output ('BUILD_OK='+$candidate+' SHA256='+$hash)
    if ($Deploy) {
        foreach($relative in $inputs.Keys) {
            if ((Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash -ne $inputs[$relative]) {
                throw "Build input changed before deployment: $relative"
            }
        }
        $dest=[IO.Path]::GetFullPath($Destination)
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $exe=Join-Path $dest 'AirPodsBuddy.exe'
        if (!(Test-Path $exe)) {throw 'First installation requires an explicit install target with an existing executable'}
        $originalHash=(Get-FileHash -LiteralPath $exe).Hash
        # Build has already succeeded. Stop only this exact installed path.
        Get-Process AirPodsBuddy -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq $exe} | ForEach-Object {Stop-Process -Id $_.Id -ErrorAction Stop;Wait-Process -Id $_.Id -Timeout 10 -ErrorAction SilentlyContinue}
        Import-Module (Join-Path $PSScriptRoot 'UpdateCore.psm1') -Force
        $token=[guid]::NewGuid().ToString('N');$receipt=Join-Path $dest ('update-health-'+$token+'.ready')
        $check={param($path)
            $p=Start-Process -FilePath $path -ArgumentList @('/update-health',$token) -WindowStyle Hidden -PassThru
            $healthy=$false
            $deadline=(Get-Date).AddSeconds(40)
            try {
                while((Get-Date)-lt $deadline -and !$p.HasExited){
                    if((Test-Path $receipt) -and (Get-Content $receipt -Raw).Trim() -eq $version){
                        Start-Sleep -Seconds 3
                        if(!$p.HasExited -and (Get-Content $receipt -Raw).Trim() -eq $version){
                            $healthy=$true
                            return $true
                        }
                        break
                    }
                    Start-Sleep -Milliseconds 250
                }
                return $false
            } finally {
                if(!$healthy -and $p -and !$p.HasExited){
                    $p.Kill()
                    $p.WaitForExit(5000)|Out-Null
                }
            }
        }
        try {
            $result=Invoke-UpdateTransaction -Candidate $candidate -Destination $exe -ExpectedHash $hash -HealthCheck $check
            try {Copy-Item (Join-Path $build 'build-manifest.json') -Destination (Join-Path $dest 'build-manifest.json') -Force}
            catch {Write-Warning ('Application is healthy; manifest copy failed: '+$_.Exception.Message)}
            Write-Output ('DEPLOY_OK='+$exe+' BACKUP='+$result.Backup)
        } catch {
            if ((Get-FileHash -LiteralPath $exe).Hash -eq $originalHash) {Start-Process -FilePath $exe -WindowStyle Hidden}
            throw
        } finally {if(Test-Path $receipt){Remove-Item -LiteralPath $receipt -Force}}
    }
} catch {Write-Error $_;exit 1} finally {Pop-Location}
