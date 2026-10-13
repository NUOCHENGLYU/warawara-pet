# Objective verification of generated sprite PNGs: transparency corners,
# opaque bbox within manifest bodyBounds, feature pixel checks.
param(
    [string]$Path = "Sources/WarawaraPet/Resources/Sprites/idle/idle_00.png",
    [int]$AlphaMin = 4
)

Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap((Resolve-Path $Path).Path)
$w = $bmp.Width; $h = $bmp.Height
"file: $Path  ${w}x${h}"

# corners must be fully transparent
$c00 = $bmp.GetPixel(0, 0).A
$c10 = $bmp.GetPixel($w - 1, 0).A
$c01 = $bmp.GetPixel(0, $h - 1).A
$c11 = $bmp.GetPixel($w - 1, $h - 1).A
"corner alphas: $c00, $c10, $c01, $c11"

# opaque bbox
$minX = $w; $maxX = -1; $minY = $h; $maxY = -1
$opaque = 0
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        if ($bmp.GetPixel($x, $y).A -ge $AlphaMin) {
            $opaque++
            if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
"opaque px: $opaque  bbox=($minX,$minY) w=$($maxX-$minX+1) h=$($maxY-$minY+1)"

# manifest bodyBounds envelope in px: x 52..148, y 54..172 logical * 2
$envX0 = 52*2; $envX1 = 148*2; $envY0 = 54*2; $envY1 = 172*2
$inside = ($minX -ge $envX0) -and ($maxX -le $envX1) -and ($minY -ge $envY0) -and ($maxY -le $envY1)
"opaque bbox inside bodyBounds envelope [$envX0..$envX1, $envY0..$envY1]: $inside"

# feature pixels (expected dark eyes near (170,244),(230,244) in 400px space)
"eye1(170,244)=$($bmp.GetPixel(170,244))  eye2(230,244)=$($bmp.GetPixel(230,244))"
"eye1Center(170,245)=$($bmp.GetPixel(170,245))"
"body(200,220)=$($bmp.GetPixel(200,220))"
"body(200,180)=$($bmp.GetPixel(200,180))"
"body bottom(200,318)=$($bmp.GetPixel(200,318))"
"mouth(200,274)=$($bmp.GetPixel(200,274))"
"armL(116,218)=$($bmp.GetPixel(116,218))  armR(284,218)=$($bmp.GetPixel(284,218))"
"footL(176,322)=$($bmp.GetPixel(176,322))  footR(224,322)=$($bmp.GetPixel(224,322))"
"behind eye gap (200,244)=$($bmp.GetPixel(200,244))"

# silhouette row widths at deciles (px)
"row profile:"
for ($d = 0; $d -lt 10; $d++) {
    $yA = [int]($minY + ($maxY - $minY) * $d / 10)
    $yB = [int]($minY + ($maxY - $minY) * ($d + 1) / 10)
    $maxW = 0
    for ($y = $yA; $y -lt $yB; $y++) {
        $rw = 0
        for ($x = $minX; $x -le $maxX; $x++) { if ($bmp.GetPixel($x, $y).A -ge $AlphaMin) { $rw++ } }
        if ($rw -gt $maxW) { $maxW = $rw }
    }
    $maxW
}
$bmp.Dispose()
