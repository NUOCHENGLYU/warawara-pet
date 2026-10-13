# Phase 4A: faithful neutral Warawara sprite generator.
#
# Draws a redesigned neutral sprite (not the old oval placeholder):
#   idle/idle_00.png       neutral
#   idle/idle_01.png       subtle breathing frame
#   sleeping/sleeping_00.png  sleeping variant (closed eyes)
#
# Design is based on the documented references (research/kimitachi007.jpg
# machine measurements + film design knowledge). All drawn features are
# CANDIDATE until the user accepts visual fidelity.
param(
    [string]$OutputDir = "Sources/WarawaraPet/Resources/Sprites"
)

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;

public static class FaithfulWarawara
{
    const int W = 400, H = 452;

    static Color C(int a, int r, int g, int b) { return Color.FromArgb(a, r, g, b); }

    static GraphicsPath BodyPath(double breath)
    {
        // Plump egg: slightly taller than wide, widest at ~55% height,
        // softly flattened bottom, gentle top rounding. Breath subtly
        // expands the lower half.
        var p = new GraphicsPath();
        double top = 130, bot = 322;
        if (breath > 0)
        {
            bot += breath * 6;
        }
        double cx = 200;
        double wL = 114, wR = 286; // body left/right at widest row
        // control points tuned for an asymmetric organic egg (not an ellipse)
        p.StartFigure();
        p.AddBezier(
            (float)cx, (float)top,
            (float)(cx + 38), (float)(top - 4),
            (float)(wR - 18), (float)(top + 10),
            (float)wR, (float)(top + 52));
        p.AddBezier(
            (float)wR, (float)(top + 52),
            (float)(wR + 6), (float)(top + 96),
            (float)(wR - 6), (float)(bot - 52),
            (float)(wR - 38), (float)(bot - 14));
        p.AddBezier(
            (float)(wR - 38), (float)(bot - 14),
            (float)(wR - 62), (float)(bot + 6),
            (float)(wL + 62), (float)(bot + 6),
            (float)(wL + 38), (float)(bot - 14));
        p.AddBezier(
            (float)(wL + 38), (float)(bot - 14),
            (float)(wL + 6), (float)(bot - 52),
            (float)(wL - 6), (float)(top + 96),
            (float)wL, (float)(top + 52));
        p.AddBezier(
            (float)wL, (float)(top + 52),
            (float)(wL + 18), (float)(top + 10),
            (float)(cx - 38), (float)(top - 4),
            (float)cx, (float)top);
        p.CloseFigure();
        return p;
    }

    static void DrawBody(Graphics g, GraphicsPath body)
    {
        // warm white base with cool shading; soft Ghibli-style cel look
        var region = new Region(body);
        var oldClip = g.Clip;
        g.SetClip(body, CombineMode.Intersect);

        // base gradient
        using (var baseBrush = new LinearGradientBrush(
            new RectangleF(114, 128, 172, 200),
            C(255, 252, 250, 246), C(255, 240, 240, 244), 90f))
        {
            g.FillPath(baseBrush, body);
        }
        // bottom crescent shadow
        using (var bottomBrush = new LinearGradientBrush(
            new RectangleF(114, 250, 172, 84),
            C(0, 214, 218, 230), C(90, 190, 196, 214), 90f))
        {
            g.FillPath(bottomBrush, body);
        }
        // soft side shadow (right), alpha very low
        using (var sideBrush = new LinearGradientBrush(
            new RectangleF(200, 128, 86, 200),
            C(0, 208, 212, 224), C(40, 222, 224, 234), 0f))
        {
            g.FillPath(sideBrush, body);
        }
        // top-left highlight
        using (var hiBrush = new LinearGradientBrush(
            new RectangleF(114, 128, 172, 60),
            C(70, 255, 255, 255), C(0, 255, 255, 255), 90f))
        {
            g.FillPath(hiBrush, body);
        }
        g.SetClip(oldClip, CombineMode.Replace);

        // soft contour
        using (var pen = new Pen(C(120, 198, 202, 216), 3f))
        {
            pen.Alignment = PenAlignment.Center;
            g.DrawPath(pen, body);
        }
    }

    static void DrawArms(Graphics g, double breath)
    {
        // small stubby side arms (subtle nubs, drawn as soft ellipses)
        double lift = breath * 2;
        DrawNub(g, 118, 212 + lift, 24, 26);  // left
        DrawNub(g, 282, 212 + lift, 24, 26);  // right
    }

    static void DrawNub(Graphics g, double cx, double cy, double w, double h)
    {
        using (var b = new SolidBrush(C(255, 250, 248, 244)))
        {
            g.FillEllipse(b, (float)(cx - w / 2), (float)(cy - h / 2), (float)w, (float)h);
        }
        using (var shade = new SolidBrush(C(50, 200, 204, 216)))
        {
            g.FillEllipse(shade, (float)(cx - w / 2 + 3), (float)(cy + h / 2 - 7), (float)(w - 6), 7);
        }
        using (var pen = new Pen(C(120, 198, 202, 216), 2.5f))
        {
            g.DrawEllipse(pen, (float)(cx - w / 2), (float)(cy - h / 2), (float)w, (float)h);
        }
    }

    static void DrawFeet(Graphics g, double breath)
    {
        // tiny feet peeking below the body, with soft ground contact
        double drop = breath * 2;
        DrawFoot(g, 176, 318 + drop, 18, 12);
        DrawFoot(g, 224, 318 + drop, 18, 12);
    }

    static void DrawFoot(Graphics g, double cx, double cy, double w, double h)
    {
        using (var b = new SolidBrush(C(255, 246, 244, 242)))
        {
            g.FillEllipse(b, (float)(cx - w / 2), (float)(cy - h / 2), (float)w, (float)h);
        }
        using (var contact = new SolidBrush(C(60, 188, 192, 206)))
        {
            g.FillEllipse(contact, (float)(cx - w / 2 - 1), (float)(cy + h / 2 - 4), (float)(w + 2), 5);
        }
        using (var pen = new Pen(C(110, 198, 202, 216), 2.5f))
        {
            g.DrawEllipse(pen, (float)(cx - w / 2), (float)(cy - h / 2), (float)w, (float)h);
        }
    }

    static void DrawEyes(Graphics g, double breath)
    {
        double ey = 244 + breath * 1.5;
        DrawEye(g, 172, ey, 30);
        DrawEye(g, 228, ey, 30);
    }

    static void DrawEye(Graphics g, double cx, double cy, double d)
    {
        // round near-black eye with a tiny warm-white highlight
        using (var b = new SolidBrush(C(255, 28, 28, 36)))
        {
            g.FillEllipse(b, (float)(cx - d / 2), (float)(cy - d / 2), (float)d, (float)d);
        }
        using (var hl = new SolidBrush(C(220, 255, 255, 255)))
        {
            g.FillEllipse(hl, (float)(cx - d / 2 + 5), (float)(cy - d / 2 + 4), (float)(d * 0.28), (float)(d * 0.28));
        }
    }

    static void DrawClosedEyes(Graphics g, double breath)
    {
        // sleeping: two soft downward arcs
        double ey = 244 + breath * 1.5;
        using (var pen = new Pen(C(255, 52, 52, 62), 5f))
        {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            g.DrawArc(pen, 155, (float)ey - 9, 30, 18, 20, 140);
            g.DrawArc(pen, 215, (float)ey - 9, 30, 18, 20, 140);
        }
    }

    static void DrawMouth(Graphics g, double breath)
    {
        // small soft smile; shape is the weakest documented feature
        double my = 274 + breath * 2;
        using (var pen = new Pen(C(255, 64, 64, 76), 4.5f))
        {
            pen.StartCap = LineCap.Round;
            pen.EndCap = LineCap.Round;
            g.DrawBezier(pen,
                (float)188, (float)(my + 2),
                (float)193, (float)(my - 3),
                (float)207, (float)(my - 3),
                (float)212, (float)(my + 2));
        }
    }

    public static Bitmap Render(string mode)
    {
        double breath = mode == "breath" ? 1.0 : (mode == "sleep" ? 0.0 : 0.0);
        var bmp = new Bitmap(W, H, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;

            var body = BodyPath(breath);
            DrawArms(g, breath);   // arms behind body edge
            DrawFeet(g, breath);
            DrawBody(g, body);
            if (mode == "sleep") DrawClosedEyes(g, breath);
            else DrawEyes(g, breath);
            DrawMouth(g, breath);
            body.Dispose();
        }
        return bmp;
    }
}
'@ -Language CSharp -ReferencedAssemblies System.Drawing

$idleDir = Join-Path $OutputDir "idle"
$sleepDir = Join-Path $OutputDir "sleeping"
New-Item -ItemType Directory -Force -Path $idleDir | Out-Null
New-Item -ItemType Directory -Force -Path $sleepDir | Out-Null

$jobs = @(
    @{ Mode = "neutral"; Path = (Join-Path $idleDir "idle_00.png") },
    @{ Mode = "breath";  Path = (Join-Path $idleDir "idle_01.png") },
    @{ Mode = "sleep";   Path = (Join-Path $sleepDir "sleeping_00.png") }
)

foreach ($job in $jobs) {
    $bmp = [FaithfulWarawara]::Render($job.Mode)
    $bmp.Save($job.Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    "wrote $($job.Path) ($($job.Mode))"
}
