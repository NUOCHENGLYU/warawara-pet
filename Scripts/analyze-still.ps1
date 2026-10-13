Add-Type -AssemblyName System.Drawing

$path = "research\kimitachi007.jpg"
$bmp = New-Object System.Drawing.Bitmap($path)

"dimensions: $($bmp.Width) x $($bmp.Height)"

# Sample-based color histogram, bucketed coarsely.
$buckets = @{}
$stepX = [Math]::Max(1, [int]($bmp.Width / 60))
$stepY = [Math]::Max(1, [int]($bmp.Height / 60))
for ($y = 0; $y -lt $bmp.Height; $y += $stepY) {
    for ($x = 0; $x -lt $bmp.Width; $x += $stepX) {
        $c = $bmp.GetPixel($x, $y)
        $r = [int]([Math]::Floor($c.R / 32) * 32)
        $g = [int]([Math]::Floor($c.G / 32) * 32)
        $b = [int]([Math]::Floor($c.B / 32) * 32)
        $key = "$r,$g,$b"
        if ($buckets.ContainsKey($key)) { $buckets[$key]++ } else { $buckets[$key] = 1 }
    }
}

"top colors (R,G,B -> count):"
$buckets.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object {
    "{0} -> {1}" -f $_.Key, $_.Value
}

# Brightness distribution (subjective proxies for character color zones).
$bright = 0; $mid = 0; $dark = 0
for ($y = 0; $y -lt $bmp.Height; $y += 3) {
    for ($x = 0; $x -lt $bmp.Width; $x += 3) {
        $c = $bmp.GetPixel($x, $y)
        $lum = (0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B)
        if ($lum -gt 200) { $bright++ } elseif ($lum -lt 80) { $dark++ } else { $mid++ }
    }
}
$total = $bright + $mid + $dark
"bright(>200): {0:P1}  mid: {1:P1}  dark(<80): {2:P1}" -f ($bright/$total), ($mid/$total), ($dark/$total)

$bmp.Dispose()
