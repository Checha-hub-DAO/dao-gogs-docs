<# 
Build-MAT-BALANCE-Weekly.ps1 — v1.1 (auto-detect Type column)
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$CsvPath,
  [datetime]$WeekEnd,
  [datetime]$WeekStart,
  [double]$TechMaxShare = 0.60,
  [double]$MinStrategicShare = 0.35
)

function Fail($msg){ Write-Host "[ERR] $msg" -ForegroundColor Red; exit 2 }

# Нормалізація мітки типу
function Map-Type([string]$raw){
  if (-not $raw) { return 'other' }
  $t = $raw.Trim().ToLowerInvariant()

  # короткі позначення
  if ($t -match '^(s|str|strategy|strategic|стратег|стратегія|стр)$') { return 'strategic' }
  if ($t -match '^(t|tech|technical|техн|техніка)$')                 { return 'technical' }

  # ключові підрядки
  if ($t -match 'strateg')         { return 'strategic' }
  if ($t -match 'тратег|тратегіч') { return 'strategic' }
  if ($t -match 'tech')            { return 'technical' }
  if ($t -match 'техн')            { return 'technical' }

  return 'other'
}

try {
  if (!(Test-Path -LiteralPath $CsvPath)) { Fail ("CSV не знайдено: {0}" -f $CsvPath) }

  $today = Get-Date
  if (-not $WeekEnd) {
    $dow = [int]$today.DayOfWeek # Sunday=0
    $shiftToSunday = ($dow + 7 - 0) % 7
    $WeekEnd = ($today.Date).AddDays(-$shiftToSunday).AddHours(23).AddMinutes(59).AddSeconds(59)
  }
  if (-not $WeekStart) { $WeekStart = ($WeekEnd.Date).AddDays(-6) }

  Write-Host ("[INFO] Інтервал: {0} .. {1}" -f $WeekStart.ToString("yyyy-MM-dd"), $WeekEnd.ToString("yyyy-MM-dd"))

  $rows = Import-Csv -LiteralPath $CsvPath
  if (-not $rows -or $rows.Count -eq 0) { Fail "CSV порожній або не містить рядків." }

  # Показати знайдені заголовки (для діагностики)
  $headers = $rows[0].PSObject.Properties.Name
  Write-Host "[INFO] Заголовки CSV:" -ForegroundColor DarkCyan
  $headers | ForEach-Object { Write-Host ("  - {0}" -f $_) }

  # Знайти колонку дати
  $dateHeader = $headers | Where-Object { $_ -match '^(Date|Дата)$' } | Select-Object -First 1
  if (-not $dateHeader) {
    # М'який пошук по фрагментах
    $dateHeader = $headers | Where-Object { $_ -match '(date|дата|day|день)' } | Select-Object -First 1
  }
  if (-not $dateHeader) { Fail "У CSV не знайдено колонку Date/Дата." }

  # Кандидати для типу (назви)
  $typeNameCandidates = $headers | Where-Object {
    $_ -match '^(Type|Тип|Category|Катег|Class|Клас|Group|Груп|Mode|Режим|Channel|Канал|Kind|Вид|Track|Трек|Area|Сфера|Domain|Домен)$'
  }

  # Якщо з назвами не пощастило — спробуємо підібрати за вмістом
  if (-not $typeNameCandidates -or $typeNameCandidates.Count -eq 0) {
    # перебір усіх колонок, шукаємо ту, де значення схожі на стратегічне/технічне
    $scored = @()
    foreach($h in $headers){
      # зберемо до 200 унікальних значень для оцінки
      $vals = ($rows | Select-Object -ExpandProperty $h -ErrorAction SilentlyContinue | Where-Object { $_ -ne $null -and $_ -ne '' } | Select-Object -First 200)
      if (-not $vals) { continue }
      $score = 0
      foreach($v in $vals){
        $m = Map-Type ($v -as [string])
        if ($m -ne 'other') { $score++ }
      }
      if ($score -gt 0) {
        $scored += [PSCustomObject]@{ Header=$h; Score=$score }
      }
    }
    $typeNameCandidates = $scored | Sort-Object Score -Descending | Select-Object -First 3 | ForEach-Object { $_.Header }
  }

  if (-not $typeNameCandidates -or $typeNameCandidates.Count -eq 0) {
    # Вивести приклади для діагностики
    Write-Host "[WARN] Не вдалося знайти колонку 'Type/Тип' за назвами або вмістом." -ForegroundColor Yellow
    Write-Host "[HINT] Перевір приклади значень по кожній колонці:" -ForegroundColor Yellow
    foreach($h in $headers){
      $samples = ($rows | Select-Object -ExpandProperty $h -ErrorAction SilentlyContinue | Where-Object { $_ } | Select-Object -Unique -First 5)
      if ($samples){
        Write-Host ("  {0}: {1}" -f $h, (($samples -join ', ')))
      }
    }
    Fail "Додай в CSV явну колонку типу (наприклад, 'Type' з 'Strategic'/'Technical') або перейменуй відповідну колонку."
  }

  # Оберемо найкращого кандидата та покажемо приклади
  $typeHeader = $typeNameCandidates | Select-Object -First 1
  Write-Host ("[INFO] Колонка типу: {0}" -f $typeHeader) -ForegroundColor DarkCyan
  $typeSamples = ($rows | Select-Object -ExpandProperty $typeHeader -ErrorAction SilentlyContinue | Where-Object { $_ } | Select-Object -Unique -First 8)
  if ($typeSamples){ Write-Host ("[INFO] Приклади значень: {0}" -f ($typeSamples -join ', ')) }

  # Опційні години
  $hoursHeader = $headers | Where-Object { $_ -match '^(Hours|Години)$' } | Select-Object -First 1

  # Нормалізація
  $normalized = foreach($r in $rows){
    $dRaw = $r.$dateHeader
    $tRaw = $r.$typeHeader
    $hRaw = $null
    if ($hoursHeader) { $hRaw = $r.$hoursHeader }

    $d = $null
    [datetime]::TryParse($dRaw, [ref]$d) | Out-Null
    if (-not $d) {
      [datetime]::TryParseExact($dRaw, @('yyyy-MM-dd','yyyy-MM-ddTHH:mm:ss','dd.MM.yyyy','dd.MM.yyyy HH:mm:ss'), $null, 'None', [ref]$d) | Out-Null
    }
    if (-not $d) { continue }

    $t = Map-Type ($tRaw -as [string])

    $h = 1.0
    if ($hoursHeader) {
      $v = $hRaw -as [double]
      if ($null -ne $v -and -not [double]::IsNaN($v)) { $h = [math]::Max(0.0, $v) }
    }

    [PSCustomObject]@{ Date=$d; Type=$t; Hours=$h }
  }

  # Фільтр тижня
  $weekData = $normalized | Where-Object { $_.Date -ge $WeekStart -and $_.Date -le $WeekEnd }
  if (-not $weekData -or $weekData.Count -eq 0) {
    Fail ("За інтервал {0}..{1} даних не знайдено." -f $WeekStart.ToString("yyyy-MM-dd"), $WeekEnd.ToString("yyyy-MM-dd"))
  }

  # Агрегація
  $sumStrategic = ($weekData | Where-Object { $_.Type -eq 'strategic' } | Measure-Object -Property Hours -Sum).Sum
  $sumTechnical = ($weekData | Where-Object { $_.Type -eq 'technical' } | Measure-Object -Property Hours -Sum).Sum
  $sumOther     = ($weekData | Where-Object { $_.Type -eq 'other'     } | Measure-Object -Property Hours -Sum).Sum

  foreach($ref in 'sumStrategic','sumTechnical','sumOther'){ if (-not (Get-Variable $ref -ValueOnly)) { Set-Variable -Name $ref -Value 0.0 } }

  $total = $sumStrategic + $sumTechnical + $sumOther
  if ($total -le 0) { Fail "Значення годин дорівнюють нулю — нічого рахувати." }

  $shareStrategic = [math]::Round(($sumStrategic / $total), 4)
  $shareTechnical = [math]::Round(($sumTechnical / $total), 4)
  $shareOther     = [math]::Round(($sumOther     / $total), 4)

  $warns = @()
  if ($shareTechnical -gt $TechMaxShare)   { $warns += ("Технічне домінує: {0:P0} > {1:P0}" -f $shareTechnical, $TechMaxShare) }
  if ($shareStrategic -lt $MinStrategicShare){ $warns += ("Низька частка стратегії: {0:P0} < {1:P0}" -f $shareStrategic, $MinStrategicShare) }

  Write-Host "------ MAT BALANCE (WEEKLY) ------" -ForegroundColor Cyan
  Write-Host ("Період      : {0} — {1}" -f $WeekStart.ToString("yyyy-MM-dd"), $WeekEnd.ToString("yyyy-MM-dd"))
  Write-Host ("Всього годин: {0:N2}" -f $total)
  Write-Host ("Стратегія   : {0:N2}  ({1:P0})" -f $sumStrategic, $shareStrategic)
  Write-Host ("Техніка     : {0:N2}  ({1:P0})" -f $sumTechnical, $shareTechnical)
  Write-Host ("Інше        : {0:N2}  ({1:P0})" -f $sumOther,     $shareOther)
  Write-Host ("----------------------------------")

  $warnText = 'OK'
  if ($warns.Count -gt 0) { $warnText = ($warns -join '; ') }
  Write-Host ("Статус: {0}" -f $warnText) -ForegroundColor ($warns.Count -gt 0 ? 'Yellow' : 'Green')

  if ($warnText -ne 'OK') { exit 2 } else { exit 0 }
}
catch {
  Write-Host ("[ERR] {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 2
}
