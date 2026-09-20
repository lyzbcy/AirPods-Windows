# Build self-contained pet popup: inline the spritesheet webp as base64.
# Usage: powershell -File webui\build_pet.ps1
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'pet.html'
$out = Join-Path $PSScriptRoot 'pet_built.html'
$webp = Join-Path $PSScriptRoot 'assets\xingxing_pet.webp'

$html = [IO.File]::ReadAllText($src)
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($webp))
$html = $html.Replace("url('assets/xingxing_pet.webp')", "url('data:image/webp;base64,$b64')")
[IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding $false))
$size = (Get-Item $out).Length
Write-Host "built: $out ($size bytes, sprite inlined)"
