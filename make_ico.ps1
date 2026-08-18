# PNG -> multi-size ICO (16/24/32/48 as BMP entries, 256 as PNG entry)
param(
    [string]$Source = ".\logo.png",
    [string]$Output = ".\assets\star_pudding.ico"
)

Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Bitmap]::FromFile($Source)

function Get-BmpEntry([System.Drawing.Bitmap]$bmp, [int]$size) {
    $resized = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($resized)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($bmp, 0, 0, $size, $size)
    $g.Dispose()

    # lock bits, read BGRA rows bottom-up
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $bmpData = $resized.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rowBytes = $size * 4
    $pixels = New-Object byte[] ($rowBytes * $size)
    for ($y = 0; $y -lt $size; $y++) {
        $srcPtr = [IntPtr]::Add($bmpData.Scan0, ($size - 1 - $y) * $bmpData.Stride)
        [System.Runtime.InteropServices.Marshal]::Copy($srcPtr, $pixels, $y * $rowBytes, $rowBytes)
    }
    $resized.UnlockBits($bmpData)
    $resized.Dispose()

    # BITMAPINFOHEADER (40 bytes), biHeight = 2*h (XOR + AND masks)
    $bih = [System.IO.MemoryStream]::new()
    $w = [System.IO.BinaryWriter]::new($bih)
    $w.Write([uint32]40); $w.Write([int32]$size); $w.Write([int32]($size * 2))
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
    $w.Write([uint32]($rowBytes * $size)); $w.Write([int32]0); $w.Write([int32]0)
    $w.Write([uint32]0); $w.Write([uint32]0)
    $w.Write($pixels)
    # AND mask: rows padded to 4-byte boundary, all zero (alpha channel decides)
    $maskRow = [math]::Floor(($size + 31) / 32) * 4
    $w.Write((New-Object byte[] ($maskRow * $size)))
    $w.Flush()
    return ,($bih.ToArray())
}

function Get-PngEntry([System.Drawing.Bitmap]$bmp, [int]$size) {
    $resized = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($resized)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($bmp, 0, 0, $size, $size)
    $g.Dispose()
    $ms = [System.IO.MemoryStream]::new()
    $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $resized.Dispose()
    return ,($ms.ToArray())
}

$sizes = @(16, 24, 32, 48)
$entries = @()
foreach ($s in $sizes) { $entries += ,@{ Size = $s; Data = (Get-BmpEntry $src $s); Png = $false } }
$entries += ,@{ Size = 256; Data = (Get-PngEntry $src 256); Png = $true }

$outMs = [System.IO.MemoryStream]::new()
$bw = [System.IO.BinaryWriter]::new($outMs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)

$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
    $dim = if ($e.Size -eq 256) { 0 } else { $e.Size }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$e.Data.Length); $bw.Write([uint32]$offset)
    $offset += $e.Data.Length
}
foreach ($e in $entries) { $bw.Write([byte[]]$e.Data) }
$bw.Flush()

$dir = Split-Path $Output
if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
[System.IO.File]::WriteAllBytes($Output, $outMs.ToArray())
$src.Dispose()

$fi = Get-Item $Output
Write-Host ("ICO OK: {0} bytes, {1} sizes" -f $fi.Length, $entries.Count)
