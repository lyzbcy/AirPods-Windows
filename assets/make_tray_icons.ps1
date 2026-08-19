# 生成托盘三态图标（学习 Mac 版的做法）：
#   face_off.ico      未连接 = face_main(可爱) + 奶油圆底
#   face_on.ico       已连接 = face_heart(心动) + 绿环
#   loading_0..5.ico  连接中 = face_cheer(加油) + 旋转弧动画帧
# 用法: powershell -File assets\make_tray_icons.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repo = Split-Path $PSScriptRoot -Parent
$src  = Join-Path $repo "webui\assets"
$outD = $PSScriptRoot
$size = 256

function Make-Base([string]$face, [switch]$GreenRing) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    if ($GreenRing) {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235,111,155,95))), 0, 0, $size, $size)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(235,255,255,255)), 12
        $g.DrawEllipse($pen, 10, 10, $size-20, $size-20)
    } else {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235,246,240,232))), 0, 0, $size, $size)
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(200,221,214,199)), 10
        $g.DrawEllipse($pen, 8, 8, $size-16, $size-16)
    }
    $faceBmp = [System.Drawing.Bitmap]::FromFile((Join-Path $src $face))
    $inner = [int]($size * 0.74); $off = [int](($size - $inner) / 2)
    $g.DrawImage($faceBmp, $off, $off, $inner, $inner)
    $faceBmp.Dispose()
    $g.Dispose()
    return ,$bmp
}

# off / on
Make-Base "face_main.png" | ForEach-Object { $_.Save("$outD\face_off.png", [System.Drawing.Imaging.ImageFormat]::Png); $_.Dispose() }
Make-Base "face_heart.png" -GreenRing | ForEach-Object { $_.Save("$outD\face_on.png", [System.Drawing.Imaging.ImageFormat]::Png); $_.Dispose() }

# loading frames: face_cheer + rotating arc
$arcPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(245,160,134,104)), 18
$arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
for ($f = 0; $f -lt 6; $f++) {
    $bmp = Make-Base "face_cheer.png"
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    # 270° 弧段，每帧旋转 60°，经典 spinner 样式
    $startDeg = -90 + ($f * 60)
    $rect = New-Object System.Drawing.Rectangle 14, 14, ($size-28), ($size-28)
    $g.DrawArc($arcPen, $rect, $startDeg, 270)
    $g.Dispose()
    $bmp.Save("$outD\loading_$f.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
$arcPen.Dispose()

# PNG -> ICO（复用仓库的 make_ico.ps1 流水线）
& (Join-Path $repo "make_ico.ps1") -Source "$outD\face_off.png" -Output "$outD\face_off.ico"
& (Join-Path $repo "make_ico.ps1") -Source "$outD\face_on.png"  -Output "$outD\face_on.ico"
for ($f = 0; $f -lt 6; $f++) {
    & (Join-Path $repo "make_ico.ps1") -Source "$outD\loading_$f.png" -Output "$outD\loading_$f.ico"
}
Write-Host "tray icons done: face_off / face_on / loading_0..5"
