Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ApprovedRelease {
    param([string]$CurrentVersion, [scriptblock]$Fetch)
    if (!$Fetch) { $Fetch = { Invoke-RestMethod -Uri 'https://api.github.com/repos/lyzbcy/AirPods-Windows/releases/latest' -Headers @{'User-Agent'='AirPodsBuddy'} -TimeoutSec 20 } }
    $release = & $Fetch
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v?(\d+\.\d+\.\d+)$') { throw 'Invalid release metadata' }
    $version = $Matches[1]
    if ([version]$version -le [version]$CurrentVersion) { return $null }
    $assets = @($release.assets | Where-Object name -CEQ 'AirPodsBuddy-Windows.zip')
    if ($assets.Count -ne 1) { throw 'Release must contain exactly one Windows archive' }
    $asset = $assets[0]
    if ($asset.browser_download_url -cnotmatch '^https://github\.com/lyzbcy/AirPods-Windows/releases/download/v?[0-9]+\.[0-9]+\.[0-9]+/AirPodsBuddy-Windows\.zip$') { throw 'Unapproved asset URL' }
    if ($asset.browser_download_url.Split('/')[-2] -cne $release.tag_name) { throw 'Release tag mismatch' }
    if (!$asset.PSObject.Properties['digest'] -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'Release has no authoritative SHA256 digest; automatic installation withheld' }
    return @{Version=$version;Url=[string]$asset.browser_download_url;Sha256=$Matches[1].ToUpperInvariant()}
}

function Expand-VerifiedUpdate {
    param([string]$Zip, [string]$Sha256, [string]$Destination)
    if ((Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash -ne $Sha256) { throw 'Archive SHA256 mismatch' }
    if (Test-Path -LiteralPath $Destination) { throw 'Staging destination already exists' }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
        $total = 0L
        foreach ($entry in $archive.Entries) {
            $total += $entry.Length
            if ($total -gt 100MB) { throw 'Archive exceeds expanded size limit' }
            $path = [IO.Path]::GetFullPath((Join-Path $root $entry.FullName))
            if (!$path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or $entry.FullName.Contains(':')) { throw 'Archive path traversal' }
            if (($entry.ExternalAttributes -shr 16 -band 0xF000) -eq 0xA000) { throw 'Archive symlink rejected' }
        }
        $files = @($archive.Entries | Where-Object FullName -CEQ 'AirPodsBuddy.exe')
        if ($files.Count -ne 1) { throw 'Expected root AirPodsBuddy.exe' }
        $exe = Join-Path $root 'AirPodsBuddy.exe'
        [IO.Compression.ZipFileExtensions]::ExtractToFile($files[0],$exe,$false)
        $stream=[IO.File]::OpenRead($exe)
        try { if ($stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) { throw 'Candidate is not a PE executable' } } finally { $stream.Dispose() }
        return $exe
    } finally { $archive.Dispose() }
}

function Invoke-UpdateTransaction {
    param([string]$Candidate,[string]$Destination,[string]$ExpectedHash,[scriptblock]$HealthCheck)
    if ((Get-FileHash -LiteralPath $Candidate -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Candidate hash mismatch' }
    if (!(Test-Path -LiteralPath $Destination -PathType Leaf)) { throw 'Installed executable missing' }
    $originalHash=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    $token=[guid]::NewGuid().ToString('N')
    $backup=$Destination+'.backup-'+$token
    $stage=$Destination+'.stage-'+$token
    Copy-Item -LiteralPath $Candidate -Destination $stage -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $stage).Hash -ne $ExpectedHash) { throw 'Staged copy hash mismatch' }
    $replaced=$false
    try {
        [IO.File]::Replace($stage,$Destination,$backup,$true)
        $replaced=$true
        if ((Get-FileHash -LiteralPath $backup).Hash -ne $originalHash) { throw 'Original backup hash mismatch' }
        if (!(& $HealthCheck $Destination)) { throw 'New application health check failed' }
        return @{Status='ok';Backup=$backup;Hash=$ExpectedHash}
    } catch {
        $reason=$_.Exception.Message
        if ($replaced) {
            if ((Get-FileHash -LiteralPath $backup).Hash -ne $originalHash) { throw 'ROLLBACK_FAILED: backup does not match original executable; no restart authorized' }
            Copy-Item -LiteralPath $backup -Destination $Destination -Force -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $Destination).Hash -ne $originalHash) { throw 'ROLLBACK_FAILED: restored executable hash mismatch; no restart authorized' }
        }
        throw "Update rolled back: $reason"
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Force }
    }
}
Export-ModuleMember -Function Get-ApprovedRelease,Expand-VerifiedUpdate,Invoke-UpdateTransaction
