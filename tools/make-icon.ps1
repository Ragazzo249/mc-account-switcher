# Minecraft 統合版 アカウント切り替え - アイコン生成
# 作者: Ragazzo249
#
# assets\app.ico を生成する。デザインを変えたいときだけ実行すればよく、
# 生成済みの .ico はリポジトリに含めてある。
#
# Minecraft の意匠は使わず、緑地に切り替えを表す双方向の矢印を描く。
#
# tako:run: powershell -NoProfile -ExecutionPolicy Bypass -File "${file}"
# tako:cwd: ${fileDir}

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outFile = Join-Path $outDir 'app.ico'

# 256px を基準に設計し、他のサイズは比率で縮める
$base = 256.0
$colBg = [System.Drawing.Color]::FromArgb(60, 133, 39)
$colFg = [System.Drawing.Color]::FromArgb(255, 255, 255)

function New-RoundedPath {
    param([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# 右向き（$Dir = 1）または左向き（$Dir = -1）の矢印を描く。
# 座標は 256px 基準で渡し、内部で倍率をかける
function Add-Arrow {
    param(
        $Graphics, $Brush, [single]$Scale,
        [single]$Left, [single]$Right, [single]$CenterY,
        [single]$Thickness, [single]$HeadW, [single]$HeadH,
        [int]$Dir
    )
    $s = { param($v) [single]($v * $Scale) }

    if ($Dir -gt 0) {
        $shaftL = $Left
        $shaftR = $Right - $HeadW
        $tipX = $Right
        $baseX = $Right - $HeadW
    } else {
        $shaftL = $Left + $HeadW
        $shaftR = $Right
        $tipX = $Left
        $baseX = $Left + $HeadW
    }

    $Graphics.FillRectangle($Brush,
        (& $s $shaftL), (& $s ($CenterY - $Thickness / 2)),
        (& $s ($shaftR - $shaftL)), (& $s $Thickness))

    $head = New-Object 'System.Drawing.PointF[]' 3
    $head[0] = New-Object System.Drawing.PointF((& $s $tipX), (& $s $CenterY))
    $head[1] = New-Object System.Drawing.PointF((& $s $baseX), (& $s ($CenterY - $HeadH / 2)))
    $head[2] = New-Object System.Drawing.PointF((& $s $baseX), (& $s ($CenterY + $HeadH / 2)))
    $Graphics.FillPolygon($Brush, $head)
}

function New-IconBitmap {
    param([int]$Size)

    $scale = $Size / $base
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $bgBrush = New-Object System.Drawing.SolidBrush($colBg)
    $fgBrush = New-Object System.Drawing.SolidBrush($colFg)

    # 背景。小さいサイズでは角丸を控えめにしないと潰れる
    $radius = [single](48 * $scale)
    if ($Size -le 32) { $radius = [single](6 * $scale * ($base / $Size) * 0.6) }
    $path = New-RoundedPath 0 0 $Size $Size $radius
    $g.FillPath($bgBrush, $path)
    $path.Dispose()

    # 上段は右向き、下段は左向き。並べて「切り替え」を表す
    Add-Arrow $g $fgBrush $scale 48 208 100 24 46 62 1
    Add-Arrow $g $fgBrush $scale 48 208 156 24 46 62 -1

    $g.Dispose()
    $bgBrush.Dispose()
    $fgBrush.Dispose()
    return $bmp
}

# ICO の 1 エントリを DIB（BITMAPINFOHEADER + XOR + AND マスク）に変換する。
# PNG 圧縮でも Explorer は表示できるが、.NET の Icon クラスなど
# 古い API が読めないため、256px 以外は互換性のある DIB で格納する
function ConvertTo-IcoDib {
    param($Bitmap)

    $w = $Bitmap.Width
    $h = $Bitmap.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $bd = $Bitmap.LockBits($rect,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $bd.Stride
    $buf = New-Object 'byte[]' ($stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $buf, 0, $buf.Length)
    $Bitmap.UnlockBits($bd)

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    # BITMAPINFOHEADER。高さは XOR と AND を合わせた 2 倍で書く決まり
    $bw.Write([UInt32]40)
    $bw.Write([Int32]$w)
    $bw.Write([Int32]($h * 2))
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]0)      # 無圧縮
    $bw.Write([UInt32]0)      # 画像サイズ（無圧縮なら 0 でよい）
    $bw.Write([Int32]0)
    $bw.Write([Int32]0)
    $bw.Write([UInt32]0)
    $bw.Write([UInt32]0)

    # ピクセルは下の行から書く
    for ($y = $h - 1; $y -ge 0; $y--) {
        $bw.Write($buf, $y * $stride, $w * 4)
    }

    # AND マスク。32bpp のアルファを使うので中身は 0 でよいが、領域は必要
    $maskStride = [int]([Math]::Floor(($w + 31) / 32) * 4)
    $zero = New-Object 'byte[]' $maskStride
    for ($y = 0; $y -lt $h; $y++) { $bw.Write($zero, 0, $maskStride) }

    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose()
    $ms.Dispose()
    # 先頭のカンマがないと byte[] が要素展開されて Object[] になり、
    # BinaryWriter.Write(byte[]) にバインドされず何も書き込まれない
    return , $bytes
}

$sizes = @(256, 128, 64, 48, 32, 16)
$images = @()
foreach ($s in $sizes) {
    $bmp = New-IconBitmap -Size $s
    if ($s -ge 256) {
        # 256px は DIB だと 256KB を超えるため、標準どおり PNG で格納する
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $ms.ToArray()
        $ms.Dispose()
    } else {
        $bytes = ConvertTo-IcoDib -Bitmap $bmp
    }
    $images += [PSCustomObject]@{ Size = $s; Bytes = $bytes }
    $bmp.Dispose()
}

$fs = [System.IO.File]::Create($outFile)
$bw = New-Object System.IO.BinaryWriter($fs)

$bw.Write([UInt16]0)                # 予約
$bw.Write([UInt16]1)                # 種別: アイコン
$bw.Write([UInt16]$images.Count)

$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
    # 256px は 0 で表す仕様
    $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
    $bw.Write([Byte]$dim)           # 幅
    $bw.Write([Byte]$dim)           # 高さ
    $bw.Write([Byte]0)              # パレット数
    $bw.Write([Byte]0)              # 予約
    $bw.Write([UInt16]1)            # プレーン数
    $bw.Write([UInt16]32)           # ビット深度
    $bw.Write([UInt32]$img.Bytes.Length)
    $bw.Write([UInt32]$offset)
    $offset += $img.Bytes.Length
}
foreach ($img in $images) {
    $payload = [byte[]]$img.Bytes
    $bw.Write($payload, 0, $payload.Length)
}

$bw.Close()
$fs.Close()

Write-Host "アイコンを生成しました: $outFile" -ForegroundColor Green
foreach ($img in $images) {
    $kind = if ($img.Size -ge 256) { 'PNG' } else { 'DIB' }
    Write-Host ("  {0,3}px  {1}  {2} bytes" -f $img.Size, $kind, $img.Bytes.Length)
}
Write-Host "  合計: $((Get-Item $outFile).Length) bytes"
