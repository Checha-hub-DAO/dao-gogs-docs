<#
  Generate-META-SymbolsPng.ps1 — v1.0.2 (SAFE-MIN)
  Генерує 8 PNG-іконок (S1..S8) у D:\CHECHA_CORE\C06_FOCUS\META_SYMBOLS
  Фікси: GraphicsUnit ok, safe Dispose, без CSV, без «розумних» лапок,
         без Split-Path -LiteralPath -Parent (використано .NET).
#>

[CmdletBinding()]
param(
  [string]$Root = "D:\CHECHA_CORE",
  [string]$OutDir,
  [int]$Size = 640,
  [switch]$UseCircle,
  [string]$FontName = "Segoe UI",
  [string]$FallbackFont = "Arial"
)

Add-Type -AssemblyName System.Drawing

function New-Brush([System.Drawing.Color]$c) { New-Object System.Drawing.SolidBrush $c }

function Luma255([System.Drawing.Color]$c) { [int](0.2126*$c.R + 0.7152*$c.G + 0.0722*$c.B) }
function TextColorFor([System.Drawing.Color]$bg) { if ((Luma255 $bg) -lt 140) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Black } }

function Get-Font([string]$name,[single]$size,[System.Drawing.FontStyle]$style){
  try   { New-Object System.Drawing.Font ($name), $size, $style, ([System.Drawing.GraphicsUnit]::Pixel) }
  catch {
    try { New-Object System.Drawing.Font ("Segoe UI"), $size, $style, ([System.Drawing.GraphicsUnit]::Pixel) }
    catch { New-Object System.Drawing.Font ("Arial"), $size, $style, ([System.Drawing.GraphicsUnit]::Pixel) }
  }
}

function Ensure-DirFromPath([string]$filePath){
  $dir = [System.IO.Path]::GetDirectoryName($filePath)
  if (![string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
  }
}

function Draw-Icon([string]$path, [System.Drawing.Color]$bg, [string]$label, [string]$title) {
  $bmp = New-Object System.Drawing.Bitmap $Size, $Size
  $g   = [System.Drawing.Graphics]::FromImage($bmp)
  $fontLabel = $null; $fontTitle = $null; $brushTxt = $null
  try {
    $g.SmoothingMode     = "AntiAlias"
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    if ($UseCircle) {
      $g.Clear([System.Drawing.Color]::Transparent)
      $brushBG = New-Brush $bg
      $rect    = New-Object System.Drawing.Rectangle 0,0,$Size,$Size
      $g.FillEllipse($brushBG, $rect); $brushBG.Dispose()
    } else {
      $g.Clear($bg)
    }

    $txtColor  = TextColorFor $bg
    $brushTxt  = New-Brush $txtColor
    $fontLabel = Get-Font -name $FontName -size ([single]($Size*0.18)) -style ([System.Drawing.FontStyle]::Bold)
    $fontTitle = Get-Font -name $FontName -size ([single]($Size*0.075)) -style ([System.Drawing.FontStyle]::Regular)

    # Label S1..S8
    $sz1 = $g.MeasureString($label, $fontLabel)
    $x1  = ($Size - $sz1.Width) / 2
    $y1  = $Size * 0.22 - $sz1.Height / 2
    $g.DrawString($label, $fontLabel, $brushTxt, $x1, $y1)

    # Title (просте скорочення, якщо довге)
    $maxW = $Size * 0.9
    $text = $title
    while (($g.MeasureString($text, $fontTitle).Width -gt $maxW) -and ($text.Length -gt 3)) {
      $text = $text.Substring(0, $text.Length - 1)
    }
    if ($text -ne $title) { $text += "…" }

    $sz2 = $g.MeasureString($text, $fontTitle)
    $x2  = ($Size - $sz2.Width) / 2
    $y2  = $Size * 0.60 - $sz2.Height / 2
    $g.DrawString($text, $fontTitle, $brushTxt, $x2, $y2)

    Ensure-DirFromPath -filePath $path
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally {
    if ($fontLabel) { try { $fontLabel.Dispose() } catch {} }
    if ($fontTitle) { try { $fontTitle.Dispose() } catch {} }
    if ($brushTxt)  { try { $brushTxt.Dispose() }  catch {} }
    if ($g)         { try { $g.Dispose() }         catch {} }
    if ($bmp)       { try { $bmp.Dispose() }       catch {} }
  }
}

# Палiтра
$C = @{
  White  = [System.Drawing.Color]::FromArgb(255,255,255)
  Gold   = [System.Drawing.Color]::FromArgb(218,165,32)
  Red    = [System.Drawing.Color]::FromArgb(200,40,40)
  Black  = [System.Drawing.Color]::FromArgb(20,20,20)
  Green  = [System.Drawing.Color]::FromArgb(40,140,60)
  Blue   = [System.Drawing.Color]::FromArgb(40,90,170)
  Violet = [System.Drawing.Color]::FromArgb(110,60,170)
}

# Дані
$data = @(
  [pscustomobject]@{ Id="S1"; Title="СВІДОМІСТЬ";   Color=$C.White  },
  [pscustomobject]@{ Id="S2"; Title="ЄДНІСТЬ";      Color=$C.Gold   },
  [pscustomobject]@{ Id="S3"; Title="ДІЯ";          Color=$C.Red    },
  [pscustomobject]@{ Id="S4"; Title="ПАМ'ЯТЬ";      Color=$C.Black  },
  [pscustomobject]@{ Id="S5"; Title="ГАРМОНІЯ";     Color=$C.Green  },
  [pscustomobject]@{ Id="S6"; Title="СИЛА";         Color=$C.Blue   },
  [pscustomobject]@{ Id="S7"; Title="ПРИРОДА";      Color=$C.Green  },
  [pscustomobject]@{ Id="S8"; Title="ДУХ-ЄДНІСТЬ";  Color=$C.Violet }
)

# Вихідний каталог
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path $Root "C06_FOCUS\META_SYMBOLS"
}
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

Write-Host "[INFO] OutDir: $OutDir"
Write-Host "[INFO] Mode: Built-in" + ($(if($UseCircle){" | circle"}{" | rect"}))

$ok = 0
foreach ($d in $data) {
  $file = Join-Path $OutDir ("{0}.png" -f $d.Id)
  Draw-Icon -path $file -bg $d.Color -label $d.Id -title $d.Title
  Write-Host "[OK]  $($d.Id) -> $file"
  $ok++
}
Write-Host "[DONE] Generated: $ok | Dir: $OutDir"
