# Build self-contained HTML: inline all images as base64 data URIs.
# Usage: pwsh build_ui.ps1
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'index.html'
$out = Join-Path $PSScriptRoot 'index_built.html'
$html = Get-Content $src -Raw -Encoding UTF8

$mime = @{
  '.png' = 'image/png'
  '.jpg' = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
}
$assets = Join-Path $PSScriptRoot 'assets'
$totalReplaced = 0
Get-ChildItem $assets -File | ForEach-Object {
  $rel = 'assets/' + $_.Name
  if ($html -cmatch [regex]::Escape($rel)) {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
    $uri = "data:$($mime[$_.Extension.ToLower()]);base64,$b64"
    $html = $html.Replace($rel, $uri)
    $totalReplaced++
  }
}
[IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding $false))
$size = (Get-Item $out).Length
Write-Host "built: $out ($size bytes, $totalReplaced images inlined)"
