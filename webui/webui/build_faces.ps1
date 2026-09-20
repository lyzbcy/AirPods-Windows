Add-Type -AssemblyName System.Drawing
$map = @{
  '第8弹-可爱.png'    = 'face_main.png'
  '第12弹-心动.png'   = 'face_heart.png'
  '第4弹-喜欢.png'    = 'face_like.png'
  '第12弹-加油.png'   = 'face_cheer.png'
}
$src = 'E:\共享\星星布丁\微信表情包\所有表情\精选'
$dst = 'E:\github\BluetoothDeviceConnector\webui\assets'
foreach ($k in $map.Keys) {
  $bmp = [System.Drawing.Bitmap]::FromFile((Join-Path $src $k))
  $sz = 256
  $nb = New-Object System.Drawing.Bitmap($sz, $sz)
  $g = [System.Drawing.Graphics]::FromImage($nb)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($bmp, 0, 0, $sz, $sz)
  $g.Dispose(); $bmp.Dispose()
  $nb.Save((Join-Path $dst $map[$k]), [System.Drawing.Imaging.ImageFormat]::Png)
  $nb.Dispose()
  $fi = Get-Item (Join-Path $dst $map[$k])
  Write-Host ($map[$k] + ' -> ' + $fi.Length + ' bytes')
}
