param(
  [Parameter(Mandatory)]
  [string]$Path,
  [switch]$NoBackup
)

if (-not (Test-Path -LiteralPath $Path)) { throw "Файл не знайдено: $Path" }

# Бекап
if (-not $NoBackup) {
  Copy-Item -LiteralPath $Path -Destination ($Path + ".funcfix.bak") -Force
}

# Читаємо файл цілком
$text = Get-Content -LiteralPath $Path -Raw

# Патерн: function Name(<args>) { <body> }, але ТІЛЬКИ якщо тіло не починається з param(
$pattern = @'
(?ms)^\s*function\s+([a-zA-Z_]\w*)\s*\(\s*([^)]*?)\s*\)\s*\{\s*(?!\s*param\s*\()(.*?)\}
'@

$rxOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase `
  -bor [System.Text.RegularExpressions.RegexOptions]::Multiline `
  -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
$regex = [regex]::new($pattern, $rxOptions)

function Normalize-Params([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return '' }
  # прибрати переноси і зайві пробіли
  $p = ($p -replace "`r?`n", ' ') -replace '\s{2,}', ' '
  # уніфікувати пробіли біля ком
  $p = ($p -replace '\s*,\s*', ', ')
  $p = $p.Trim()
  return $p
}

# Замінювач: function Name(args){ body } -> function Name { param(args) body }
$evaluator = {
  param($m)
  $name   = $m.Groups[1].Value
  $params = Normalize-Params $m.Groups[2].Value
  $body   = $m.Groups[3].Value

  $nl = "`r`n"
  $new = "function $name {" + $nl
  if ($params -ne '') {
    $new += "  param($params)" + $nl
  } else {
    $new += "  param()" + $nl
  }

  if ([string]::IsNullOrWhiteSpace($body)) {
    $new += $nl
  } else {
    # легке вирівнювання тіла з відступом 2 пробіли
    $new += "  " + ($body -replace "`r?`n", "$nl  ").TrimEnd() + $nl
  }
  $new += "}" + $nl
  return $new
}

$fixed = $regex.Replace($text, $evaluator)

# Запис у UTF-8 без BOM
$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($Path, $fixed, $enc)

"✅ Функції відформатовано. Бекап: $Path.funcfix.bak"
