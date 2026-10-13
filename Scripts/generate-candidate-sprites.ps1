# Generates the CANDIDATE Warawara sprite frames (deterministic, originally
# created, NOT traced from the film frame) into
# Sources/WarawaraPet/Resources/Sprites/<animation>/ and writes sprites.json.
#
# CANDIDATE — awaiting visual approval. Replace by hand-corrected PNGs and an
# edited sprites.json at any time.
#
# Usage (Windows, PowerShell 5.1):
#   powershell -ExecutionPolicy Bypass -File Scripts\generate-candidate-sprites.ps1
Add-Type -AssemblyName System.Drawing

$outRoot = Join-Path $PSScriptRoot "..\Sources\WarawaraPet\Resources\Sprites"
$scale = 2

# Logical geometry (points). Matches PetMetrics so candidate sprites land
# exactly where the procedural placeholder does.
$canvasW = 200
$canvasH = 226
$bodyW = 96
$bodyH = 118
$bodyCX = 100
$bodyCY = 113

function New-RectF([double]$x, [double]$y, [double]$w, [double]$h) {
    New-Object System.Drawing.RectangleF($x, $y, $w, $h)
}

function New-CanvasBitmap {
    New-Object System.Drawing.Bitmap(($canvasW * $scale), ($canvasH * $scale), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Draw-Blob($g, [float]$bw, [float]$bh, [string]$eyeMode, [float]$eyeShiftY) {
    $s = [double]$scale
    $cx = [double]$bodyCX
    $cy = [double]$bodyCY

    # Body: soft white gradient, slightly cool at the bottom.
    $rect = New-RectF (($cx - $bw / 2) * $s) (($cy - $bh / 2) * $s) ($bw * $s) ($bh * $s)
    $top = [System.Drawing.Color]::FromArgb(255, 253, 253, 255)
    $bottom = [System.Drawing.Color]::FromArgb(255, 213, 218, 232)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, 90.0)
    $g.FillEllipse($brush, $rect)
    $brush.Dispose()

    # Subtle inner shading near the bottom.
    $shadeRect = New-RectF (($cx - $bw / 2 + 6) * $s) (($cy + $bh * 0.18) * $s) (($bw - 12) * $s) ($bh * 0.30 * $s)
    $shadeBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(58, 168, 176, 198))
    $g.FillEllipse($shadeBrush, $shadeRect)
    $shadeBrush.Dispose()

    # Soft outline.
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(88, 138, 144, 162), (2.0 * $s))
    $g.DrawEllipse($pen, $rect)
    $pen.Dispose()

    # Eyes: small dark ovals.
    $eyeW = [double]14
    $eyeH = [double]19
    $eyeSpacing = [double]34
    $eyeY = $cy - 24 + $eyeShiftY
    $eyeColor = [System.Drawing.Color]::FromArgb(255, 26, 26, 30)
    $eyeBrush = New-Object System.Drawing.SolidBrush($eyeColor)
    foreach ($side in @(-1, 1)) {
        $ex = $cx + $side * ($eyeSpacing / 2) - $eyeW / 2
        $ey = $eyeY - $eyeH / 2
        $eyeRect = New-RectF ($ex * $s) ($ey * $s) ($eyeW * $s) ($eyeH * $s)
        if ($eyeMode -eq 'sleeping') {
            $arcPen = New-Object System.Drawing.Pen($eyeColor, (3.0 * $s))
            $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawArc($arcPen, $eyeRect, 25, 130)
            $arcPen.Dispose()
        } else {
            $g.FillEllipse($eyeBrush, $eyeRect)
            if ($eyeMode -eq 'sleepy') {
                $lidBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 239, 240, 246))
                $lidRect = New-RectF ($ex * $s) (($ey - $eyeH * 0.10) * $s) ($eyeW * $s) ($eyeH * 0.62 * $s)
                $g.FillEllipse($lidBrush, $lidRect)
                $lidBrush.Dispose()
            }
        }
    }
    $eyeBrush.Dispose()

    # Mouth: tiny soft pink oval.
    $mouthBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 226, 132, 138))
    $mouthRect = New-RectF (($cx - 5) * $s) (($cy + 26) * $s) (10 * $s) (7 * $s)
    $g.FillEllipse($mouthBrush, $mouthRect)
    $mouthBrush.Dispose()
}

function Save-Frame([string]$dirName, [string]$frameName, [float]$bw, [float]$bh, [string]$eyeMode, [float]$eyeShiftY) {
    $dir = Join-Path $outRoot $dirName
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $bmp = New-CanvasBitmap
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    Draw-Blob $g $bw $bh $eyeMode $eyeShiftY
    $g.Dispose()
    $path = Join-Path $dir "$frameName.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $path"
}

Save-Frame "idle" "idle_00" 96 118 "open" 0
Save-Frame "idle" "idle_01" 101 111 "open" 0
Save-Frame "hop" "hop_00" 106 100 "open" 0
Save-Frame "hop" "hop_01" 86 126 "open" 0
Save-Frame "hop" "hop_02" 110 94 "open" 0
Save-Frame "float" "float_00" 90 124 "open" 0
Save-Frame "float" "float_01" 96 118 "open" 0
Save-Frame "float" "float_02" 102 110 "open" 0
Save-Frame "curious" "curious_00" 96 118 "open" 2
Save-Frame "clicked" "clicked_00" 108 92 "open" 0
Save-Frame "dragged" "dragged_00" 96 118 "open" 0
Save-Frame "settling" "settling_00" 98 112 "open" 0
Save-Frame "sleepy" "sleepy_00" 96 118 "sleepy" 0
Save-Frame "sleeping" "sleeping_00" 98 112 "sleeping" 0
Save-Frame "wake" "wake_00" 96 118 "open" 0

$manifest = @"
{
  "version": 1,
  "layout": {
    "canvas": { "width": 200, "height": 226 },
    "anchor": { "x": 0.5, "y": 0.5 },
    "bodyBounds": { "x": 0.26, "y": 0.239, "width": 0.48, "height": 0.522 }
  },
  "animations": {
    "idle":     { "frames": ["idle/idle_00.png", "idle/idle_01.png"], "frameDuration": 0.6, "loop": true },
    "hop":      { "frames": ["hop/hop_00.png", "hop/hop_01.png", "hop/hop_02.png"], "frameDuration": 0.08, "loop": false },
    "float":    { "frames": ["float/float_00.png", "float/float_01.png", "float/float_02.png"], "frameDuration": 0.15, "loop": true },
    "curious":  { "frames": ["curious/curious_00.png"], "frameDuration": 0.1, "loop": false },
    "clicked":  { "frames": ["clicked/clicked_00.png"], "frameDuration": 0.1, "loop": false },
    "dragged":  { "frames": ["dragged/dragged_00.png"], "frameDuration": 0.1, "loop": false },
    "settling": { "frames": ["settling/settling_00.png"], "frameDuration": 0.1, "loop": false },
    "sleepy":   { "frames": ["sleepy/sleepy_00.png"], "frameDuration": 0.1, "loop": false },
    "sleeping": { "frames": ["sleeping/sleeping_00.png"], "frameDuration": 0.1, "loop": false },
    "wake":     { "frames": ["wake/wake_00.png"], "frameDuration": 0.1, "loop": false }
  }
}
"@
$manifestPath = Join-Path $outRoot "sprites.json"
[System.IO.File]::WriteAllText($manifestPath, $manifest)
Write-Host "wrote $manifestPath"

# Self-verification: reload one frame and check the alpha channel.
$check = [System.Drawing.Bitmap]::FromFile((Join-Path $outRoot "idle\idle_00.png"))
$corner = $check.GetPixel(0, 0)
$center = $check.GetPixel([int]($check.Width / 2), [int]($check.Height / 2))
Write-Host ("verify: corner alpha={0} center alpha={1} size={2}x{3}" -f $corner.A, $center.A, $check.Width, $check.Height)
$check.Dispose()
