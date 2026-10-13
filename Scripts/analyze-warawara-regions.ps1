# Region analysis v3: per-warawara analysis around local brightness maxima.
# Objective measurements only.
param(
    [string]$ImagePath = "research/kimitachi007.jpg",
    [double]$MaxMinLum = 182,
    [double]$GrowThreshold = 170,
    [int]$MinSeparation = 30,
    [int]$Window = 46,
    [int]$MaxCandidates = 14
)

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;

public static class WarawaraLocal
{
    public sealed class Candidate
    {
        public int CX, CY, Peak;
        public int X, Y, W, H, Area;
        public double Fill, Aspect;
        public List<int[]> Holes = new List<int[]>();
        public int[] RowProfile = new int[10]; // width at deciles, normalized
    }

    public static Candidate[] Run(string path, double maxMinLum, double growThr, int minSep, int window, int maxCandidates)
    {
        using (var bmp = new Bitmap(path))
        {
            int w = bmp.Width, h = bmp.Height;
            double[,] lum = new double[w, h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    Color c = bmp.GetPixel(x, y);
                    lum[x, y] = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B;
                }

            // box blur radius 4
            double[,] blurred = new double[w, h];
            for (int y = 4; y < h - 4; y++)
                for (int x = 4; x < w - 4; x++)
                {
                    double s = 0;
                    for (int dy = -4; dy <= 4; dy++)
                        for (int dx = -4; dx <= 4; dx++)
                            s += lum[x + dx, y + dy];
                    blurred[x, y] = s / 81.0;
                }

            // local maxima with min separation
            var maxima = new List<int[]>();
            for (int y = 8; y < h - 8; y++)
                for (int x = 8; x < w - 8; x++)
                {
                    double v = blurred[x, y];
                    if (v < maxMinLum) continue;
                    bool isMax = true;
                    for (int dy = -3; dy <= 3 && isMax; dy++)
                        for (int dx = -3; dx <= 3; dx++)
                            if (blurred[x + dx, y + dy] > v) { isMax = false; break; }
                    if (!isMax) continue;
                    bool tooClose = false;
                    foreach (var m in maxima)
                    {
                        if (Math.Abs(m[0] - x) < minSep && Math.Abs(m[1] - y) < minSep) { tooClose = true; break; }
                    }
                    if (!tooClose) maxima.Add(new[] { x, y });
                }
            maxima.Sort((a, b) => b[2].CompareTo(a[2]) == 0 ? 0 : (blurred[b[0], b[1]].CompareTo(blurred[a[0], a[1]])));
            var best = new List<int[]>();
            foreach (var m in maxima)
            {
                bool tooClose = false;
                foreach (var b in best)
                {
                    if (Math.Abs(b[0] - m[0]) < minSep && Math.Abs(b[1] - m[1]) < minSep) { tooClose = true; break; }
                }
                if (!tooClose) best.Add(m);
                if (best.Count >= maxCandidates) break;
            }

            var result = new List<Candidate>();
            foreach (var m in best)
            {
                int cx = m[0], cy = m[1];
                int x0 = Math.Max(0, cx - window), y0 = Math.Max(0, cy - window);
                int x1 = Math.Min(w - 1, cx + window), y1 = Math.Min(h - 1, cy + window);
                // flood-fill bright region from center within window
                var stack = new int[(2 * window + 1) * (2 * window + 1) * 2];
                var seen = new HashSet<int>();
                int sp = 0;
                stack[sp++] = cx; stack[sp++] = cy; seen.Add(cy * w + cx);
                int minX = cx, maxX = cx, minY = cy, maxY = cy, area = 0;
                while (sp > 0)
                {
                    int py = stack[--sp], px = stack[--sp];
                    area++;
                    if (px < minX) minX = px; if (px > maxX) maxX = px;
                    if (py < minY) minY = py; if (py > maxY) maxY = py;
                    for (int d = 0; d < 4; d++)
                    {
                        int nx = px, ny = py;
                        if (d == 0) nx++; else if (d == 1) nx--; else if (d == 2) ny++; else ny--;
                        if (nx < x0 || nx > x1 || ny < y0 || ny > y1) continue;
                        if (lum[nx, ny] < growThr) continue;
                        int key = ny * w + nx;
                        if (seen.Contains(key)) continue;
                        seen.Add(key);
                        stack[sp++] = nx; stack[sp++] = ny;
                    }
                }
                if (area < 60 || maxX - minX < 12 || maxY - minY < 12) continue;
                var cand = new Candidate
                {
                    CX = cx, CY = cy,
                    X = minX, Y = minY, W = maxX - minX + 1, H = maxY - minY + 1, Area = area,
                    Peak = (int)Math.Round(blurred[cx, cy])
                };
                cand.Fill = (double)area / (cand.W * cand.H);
                cand.Aspect = (double)cand.W / cand.H;

                // holes inside the mask (dark enclosed regions)
                var holeSeen = new HashSet<int>();
                for (int y = minY; y <= maxY; y++)
                    for (int x = minX; x <= maxX; x++)
                    {
                        if (!(lum[x, y] < 80)) continue;
                        int key = y * w + x;
                        if (holeSeen.Contains(key)) continue;
                        int hsp = 0;
                        stack[hsp++] = x; stack[hsp++] = y; holeSeen.Add(key);
                        int hx0 = x, hx1 = x, hy0 = y, hy1 = y, harea = 0;
                        bool touches = false;
                        while (hsp > 0)
                        {
                            int py = stack[--hsp], px = stack[--hsp]; harea++;
                            if (px < hx0) hx0 = px; if (px > hx1) hx1 = px;
                            if (py < hy0) hy0 = py; if (py > hy1) hy1 = py;
                            if (px <= minX || px >= maxX || py <= minY || py >= maxY) touches = true;
                            for (int d = 0; d < 4; d++)
                            {
                                int nx = px, ny = py;
                                if (d == 0) nx++; else if (d == 1) nx--; else if (d == 2) ny++; else ny--;
                                if (nx < minX || nx > maxX || ny < minY || ny > maxY) continue;
                                if (!(lum[nx, ny] < 80)) continue;
                                int nkey = ny * w + nx;
                                if (holeSeen.Contains(nkey)) continue;
                                holeSeen.Add(nkey);
                                stack[hsp++] = nx; stack[hsp++] = ny;
                            }
                        }
                        if (touches || harea < 2 || harea > area / 8) continue;
                        cand.Holes.Add(new[] { (hx0 + hx1) / 2 - minX, (hy0 + hy1) / 2 - minY, harea });
                    }
                cand.Holes.Sort((a, b) => b[2].CompareTo(a[2]));

                // row profile deciles
                for (int d = 0; d < 10; d++)
                {
                    int yA = minY + cand.H * d / 10;
                    int yB = minY + cand.H * (d + 1) / 10;
                    int maxW = 0;
                    for (int y = yA; y < yB; y++)
                    {
                        int rw = 0;
                        for (int x = minX; x <= maxX; x++)
                        {
                            if (lum[x, y] >= growThr && seen.Contains(y * w + x)) rw++;
                        }
                        if (rw > maxW) maxW = rw;
                    }
                    cand.RowProfile[d] = maxW;
                }
                result.Add(cand);
            }
            return result.ToArray();
        }
    }

    public static string Ascii(Candidate c)
    {
        int cols = 36, rows = 16;
        var sb = new System.Text.StringBuilder();
        var fs = new List<string>();
        for (int r = 0; r < rows; r++)
        {
            int y0 = c.Y + c.H * r / rows;
            int y1 = c.Y + c.H * (r + 1) / rows;
            var line = new char[cols];
            for (int i = 0; i < cols; i++) line[i] = ' ';
            double maxW = Math.Max(1, c.W);
            // use row profile of mask via bbox scan is expensive; approximate from RowProfile deciles
            for (int d = 0; d < 10; d++)
            {
                int dY0 = d * rows / 10, dY1 = (d + 1) * rows / 10;
                if (r < dY0 || r >= dY1) continue;
                int wpx = c.RowProfile[d];
                double frac = (double)wpx / maxW;
                int half = (int)Math.Round(frac * cols / 2.0);
                if (half < 0) half = 0; if (half > cols / 2 - 1) half = cols / 2 - 1;
                line[cols / 2 - half] = '#';
                line[cols / 2 + half] = '#';
            }
            foreach (var hole in c.Holes)
            {
                if (hole[1] >= y0 - c.Y && hole[1] < y1 - c.Y)
                {
                    int hx = (int)Math.Round((double)hole[0] / maxW * (cols - 1));
                    if (hx >= 0 && hx < cols) line[hx] = 'o';
                }
            }
            sb.AppendLine(new string(line));
        }
        return sb.ToString();
    }
}
"@ -Language CSharp -ReferencedAssemblies System.Drawing

$full = (Resolve-Path $ImagePath).Path
$cands = [WarawaraLocal]::Run($full, $MaxMinLum, $GrowThreshold, $MinSeparation, $Window, $MaxCandidates)
"candidates: $($cands.Count)"
foreach ($c in $cands) {
    "center=({0},{1}) peak={2} bbox=({3},{4}) {5}x{6} aspect={7} fill={8} holes={9}" -f `
        $c.CX, $c.CY, $c.Peak, $c.X, $c.Y, $c.W, $c.H, [math]::Round($c.Aspect, 3), [math]::Round($c.Fill, 2), $c.Holes.Count
    $h = $c.Holes | Select-Object -First 4 | ForEach-Object { "rel=({0},{1}) a={2}" -f [math]::Round($_[0] / $c.W, 3), [math]::Round($_[1] / $c.H, 3), $_[2] }
    if ($h) { $h | ForEach-Object { "      hole $_" } }
    "profile: $($c.RowProfile -join ',')"
    [WarawaraLocal]::Ascii($c)
    ""
}
