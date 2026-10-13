# Crop-based analysis of a single warawara region in the reference still.
param(
    [string]$ImagePath = "research/kimitachi007.jpg",
    [int]$CropX = 50, [int]$CropY = 845, [int]$CropW = 110, [int]$CropH = 160,
    [double]$Threshold = 172,
    [int]$Cols = 60, [int]$Rows = 32
)

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;

public static class WarawaraCrop
{
    public static string Render(string path, int x0, int y0, int w, int h, double thr, int cols, int rows)
    {
        var sb = new System.Text.StringBuilder();
        using (var bmp = new Bitmap(path))
        {
            int iw = bmp.Width, ih = bmp.Height;
            var mask = new byte[w, h];
            int bright = 0, dark = 0;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int ix = x0 + x, iy = y0 + y;
                    if (ix < 0 || ix >= iw || iy < 0 || iy >= ih) continue;
                    Color c = bmp.GetPixel(ix, iy);
                    double lum = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B;
                    if (lum >= thr) { mask[x, y] = 1; bright++; }
                    else if (lum < 82) { mask[x, y] = 2; dark++; }
                }
            sb.AppendLine("bright=" + bright + " dark=" + dark);
            // row widths
            var widths = new int[h];
            for (int y = 0; y < h; y++)
            {
                int rw = 0;
                for (int x = 0; x < w; x++) if (mask[x, y] == 1) rw++;
                widths[y] = rw;
            }
            for (int r = 0; r < rows; r++)
            {
                int yA = r * h / rows, yB = (r + 1) * h / rows;
                var line = new char[cols];
                for (int i = 0; i < cols; i++) line[i] = ' ';
                for (int y = yA; y < yB; y++)
                {
                    if (widths[y] == 0) continue;
                    int maxW = 0;
                    for (int y2 = yA; y2 < yB; y2++) if (widths[y2] > maxW) maxW = widths[y2];
                    double frac = (double)(maxW - 1) / Math.Max(1, w - 1);
                    int half = (int)Math.Round(frac * cols / 2.0);
                    if (half < 0) half = 0; if (half >= cols / 2) half = cols / 2 - 1;
                    line[cols / 2 - half] = '#';
                    line[cols / 2 + half] = '#';
                }
                for (int y = yA; y < yB; y++)
                    for (int x = 0; x < w; x++)
                    {
                        if (mask[x, y] != 2) continue;
                        int cx = (int)Math.Round((double)x / Math.Max(1, w - 1) * (cols - 1));
                        if (cx >= 0 && cx < cols && line[cx] == ' ') line[cx] = '*';
                    }
                sb.AppendLine(new string(line));
            }
            // row profile decile summary
            sb.Append("profile: ");
            for (int d = 0; d < 10; d++)
            {
                int yA = d * h / 10, yB = (d + 1) * h / 10, maxW = 0;
                for (int y = yA; y < yB; y++) if (widths[y] > maxW) maxW = widths[y];
                sb.Append(maxW).Append(',');
            }
        }
        return sb.ToString();
    }
}
'@ -Language CSharp -ReferencedAssemblies System.Drawing

$full = (Resolve-Path $ImagePath).Path
"crop: ($CropX,$CropY) ${CropW}x${CropH} thr=$Threshold"
[WarawaraCrop]::Render($full, $CropX, $CropY, $CropW, $CropH, $Threshold, $Cols, $Rows)
