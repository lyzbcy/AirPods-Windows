Add-Type -AssemblyName System.Drawing
# faces -> 192px PNG (keep transparency), QR -> 256px wide JPEG q85
$dst = 'E:\github\BluetoothDeviceConnector\webui\assets'
$faces = @{
  'E:\共享\星星布丁\微信表情包\所有表情\精选\第8弹-可爱.png'    = 'face_main.png'
  'E:\共享\星星布丁\微信表情包\所有表情\精选\第12弹-心动.png'   = 'face_heart.png'
  'E:\共享\星星布丁\微信表情包\所有表情\精选\第4弹-喜欢.png'    = 'face_like.png'
  'E:\共享\星星布丁\微信表情包\所有表情\精选\第12弹-加油.png'   = 'face_cheer.png'
}
foreach ($k in $faces.Keys) {
  $bmp = [System.Drawing.Bitmap]::FromFile($k)
  $nb = New-Object System.Drawing.Bitmap(192, 192)
  $g = [System.Drawing.Graphics]::FromImage($nb)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($bmp, 0, 0, 192, 192)
  $g.Dispose(); $bmp.Dispose()
  $nb.Save((Join-Path $dst $faces[$k]), [System.Drawing.Imaging.ImageFormat]::Png)
  $nb.Dispose()
}
$qrs = @('qq-group.jpg', 'reward-qr.jpg')
foreach ($q in $qrs) {
  $bmp = [System.Drawing.Bitmap]::FromFile((Join-Path $dst $q))
  $w = 240; $h = [int]($bmp.Height * $w / $bmp.Width)
  $nb = New-Object System.Drawing.Bitmap($w, $h)
  $g = [System.Drawing.Graphics]::FromImage($nb)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($bmp, 0, 0, $w, $h)
  $g.Dispose(); $bmp.Dispose()
  $jp = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
  $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]85)
  $nb.Save((Join-Path $dst $q), $jp, $ep)
  $nb.Dispose()
}
# sticker-qr.png -> 240px PNG (QR needs sharp edges)
$bmp = [System.Drawing.Bitmap]::FromFile((Join-Path $dst 'sticker-qr.png'))
$w = 240; $h = [int]($bmp.Height * $w / $bmp.Width)
$nb = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($nb)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($bmp, 0, 0, $w, $h)
$g.Dispose(); $bmp.Dispose()
$nb.Save((Join-Path $dst 'sticker-qr.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$nb.Dispose()
Get-ChildItem $dst -File | ForEach-Object { Write-Host ($_.Name + ' ' + $_.Length) }
