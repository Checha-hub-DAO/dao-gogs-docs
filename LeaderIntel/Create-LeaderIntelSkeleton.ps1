param(
  [string]$Root = "D:\LeaderIntel",
  [string]$Name = "LeaderIntel"
)

$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$base = Join-Path $Root "pkg\$Name"

# 0) Папки
$dirs = @(
  "$base\scripts",
  "$base\rules",
  "$base\reports",
  "$base\data",
  "$base\docs"
)
$dirs | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

# 1) Скрипти (копіюємо наявні, якщо є; інакше кладемо заглушки)
$src = @{
  "Run-LeaderIntelPipeline.ps1" = "D:\Scripts\Run-LeaderIntelPipeline.ps1";
  "Apply-IntelFilters.ps1"      = "D:\Scripts\Apply-IntelFilters.ps1";
  "Check-IntelBeacons.ps1"      = "D:\Scripts\Check-IntelBeacons.ps1";
  "Export-DigestHtml.ps1"       = "D:\Scripts\Export-DigestHtml.ps1";
  "Render-ToxicRadar.ps1"       = "D:\Scripts\Render-ToxicRadar.ps1";
  "Set-IntelProfile.ps1"        = "D:\Scripts\Set-IntelProfile.ps1"
}
foreach($k in $src.Keys){
  $dst = Join-Path "$base\scripts" $k
  if (Test-Path $src[$k]) { Copy-Item $src[$k] $dst -Force }
  elseif (-not (Test-Path $dst)) {
    "# placeholder for $k" | Set-Content -Encoding UTF8 $dst
  }
}

# 2) Конфіги правил (soft/hard + beacons)
@'
{
  "domain_rules": {
    "blocklist": ["rutube.ru","vk.com","ok.ru","zen.yandex","sputniknews","ria.ru","tsargrad.tv","roskomnadzor"],
    "allowlist": ["youtube.com","youtu.be","t.me","x.com","twitter.com","facebook.com","instagram.com"],
    "watchlist": ["rumble.com","boosty.to","telegram.org/?lang=ru"]
  },
  "keyword_rules": {
    "toxic": [
      { "pattern": "(русский мир|русск(ий|ій) м(и|і)р|рускомир)", "weight": 60 },
      { "pattern": "(антизахідн(а|ий)|антиевроп|антинато|за мир будь-якою ціною)", "weight": 30 },
      { "pattern": "(капітул(яц|яції)|зрада\\b|колаборант|\".*нацисти\")", "weight": 25 }
    ],
    "ally": [{ "pattern": "(ЗСУ|Збройн(і|их) Сил|донейт|волонтер|пункт незламності)", "weight": 35 }],
    "risk": [{ "pattern": "(маніпул(яц|яції)|фейк|бот(и|ів)?|дезінформ)", "weight": 25 }]
  },
  "toxicity_map": { "низька": 10, "середня": 55, "висока": 85 },
  "thresholds": { "block": 80, "warn": 45 }
}
'@ | Set-Content -Encoding UTF8 "$base\rules\filters.hard.json"

@'
{
  "domain_rules": {
    "blocklist": ["rutube.ru","vk.com","ok.ru","zen.yandex","sputniknews","ria.ru","tsargrad.tv","roskomnadzor"],
    "allowlist": ["youtube.com","youtu.be","t.me","x.com","twitter.com","facebook.com","instagram.com"],
    "watchlist": ["rumble.com","boosty.to","telegram.org/?lang=ru"]
  },
  "keyword_rules": {
    "toxic": [
      { "pattern": "(русский мир|русск(ий|ій) м(и|і)р|рускомир)", "weight": 50 },
      { "pattern": "(антизахідн(а|ий)|антиевроп|антинато|за мир будь-якою ціною)", "weight": 25 },
      { "pattern": "(капітул(яц|яції)|зрада\\b|колаборант|\".*нацисти\")", "weight": 20 }
    ],
    "ally": [{ "pattern": "(ЗСУ|Збройн(і|их) Сил|донейт|волонтер|пункт незламності)", "weight": 30 }],
    "risk": [{ "pattern": "(маніпул(яц|яції)|фейк|бот(и|ів)?|дезінформ)", "weight": 20 }]
  },
  "toxicity_map": { "низька": 10, "середня": 55, "висока": 85 },
  "thresholds": { "block": 60, "warn": 25 }
}
'@ | Set-Content -Encoding UTF8 "$base\rules\filters.soft.json"

@'
{
  "spikes": { "audience_growth_percent": 20, "window_days": 7 },
  "toxicity_change": { "to_level": "висока" },
  "keywords": [
    { "name": "RF-наратив",   "pattern": "(русский мир|антиевроп|за мир будь-якою ціною)" },
    { "name": "атака на ЗСУ", "pattern": "(дискредитац(ія|ия)\\s+ЗСУ|\\bЗСУ\\b.*(некомпетентні|злочинні))" },
    { "name": "маніпуляція",  "pattern": "(маніпул(яц|яції)|дезінформ|тотальна зрада)" }
  ]
}
'@ | Set-Content -Encoding UTF8 "$base\rules\beacons.json"

# 3) Репорти-заглушки
"# Прапорці фільтрації`r`n(нема спрацювань)" | Set-Content -Encoding UTF8 "$base\reports\Flags.md"
"# Алерти маяків`r`n(спрацювань немає)"      | Set-Content -Encoding UTF8 "$base\reports\Alerts.md"
"# Журнал`r`n(порожньо)"                      | Set-Content -Encoding UTF8 "$base\reports\LeaderIntel_Log.md"
"# Токсичний радар`r`n(не згенеровано)"       | Set-Content -Encoding UTF8 "$base\reports\ToxicRadar.md"

# 4) Дані (мінімальний Leaders.csv)
@'
Ім’я,Роль / Професія,Організація,Канал,Позиції,Теми,Аудиторія,Союзники,Опоненти,Ризики,Потенціал DAO-GOGS,Статус
"Сергій Стерненко","Активіст, блогер","-","https://www.youtube.com/@sternenko","Антиросійська, проукраїнська","Оборона, права","1М+","","","","Мобілізація молоді","Ядро"
'@ | Set-Content -Encoding UTF8 "$base\data\Leaders.csv"

# 5) Документація (мінімальна)
@'
# LeaderIntel — Інтелектуальний радар середовища

**Призначення.** Система OSINT-аналітики для моніторингу лідерів/каналів, фільтрації токсичних потоків, виявлення маяків (загроз/трендів) і формування звітів.

## Ключові модулі
- Розвідка інформаційних воєн (виявлення ворожих наративів)
- Щит інформаційного поля (фільтри + маяки)
- Радар токсичності (візуалізація)
- Дайджести/Журнали (оперативна звітність)

## Швидкий старт
1) Перевірити/підставити скрипти у `scripts\`.  
2) Запустити:  
   - `scripts\Apply-IntelFilters.ps1 -Profile hard`  
   - `scripts\Check-IntelBeacons.ps1`  
   - `scripts\Export-DigestHtml.ps1 -Open`
'@ | Set-Content -Encoding UTF8 "$base\docs\README.md"

@'
# Архітектура

- `scripts\Run-LeaderIntelPipeline.ps1` — конвеєр збору/обробки/звітності  
- `scripts\Apply-IntelFilters.ps1` — фільтри (soft/hard), Visibility  
- `scripts\Check-IntelBeacons.ps1` — маяки: ключові слова, токсичність  
- `scripts\Export-DigestHtml.ps1` — HTML дайджест із Markdown  
- `rules\*.json` — конфіги правил і маяків  
- `data\Leaders.csv` — вхідні профілі/канали  
- `reports\` — результати: Flags.md, Alerts.md, Digest_*.html, Log

**Потік:** data → filters → beacons → digest(html)
'@ | Set-Content -Encoding UTF8 "$base\docs\ARCHITECTURE.md"

@'
# Принципи роботи

1. Прозорі правила (JSON), відтворюваність результатів.  
2. Розділення режимів: *soft* для калібрування, *hard* для прод.  
3. Мінімум зовнішніх залежностей, сумісність PowerShell 5/7.  
4. Логи і дайджести — як джерело правок і аудиту.  
5. Етичні рамки: не використовувати несанкціоновані джерела/інструменти.
'@ | Set-Content -Encoding UTF8 "$base\docs\PRINCIPLES.md"

@'
# Операції

- **Добові/тижневі завдання** через Windows Task Scheduler.  
- Змінна оточення `LEADERINTEL_PROFILE=soft|hard` керує профілем фільтрів.  
- Резервні копії `dist\*.zip` із SHA256-хешем.

## Типові команди
- `scripts\Apply-IntelFilters.ps1 -Profile hard`
- `scripts\Check-IntelBeacons.ps1`
- `scripts\Export-DigestHtml.ps1 -Open`
'@ | Set-Content -Encoding UTF8 "$base\docs\OPERATIONS.md"

@'
# Безпека

- Конфіги правил — версіонуються (зміни документуються в Log).  
- Жодних секретів у репозиторії/ZIP.  
- Дані лише з публічного простору; персональні дані — мінімізовані.
'@ | Set-Content -Encoding UTF8 "$base\docs\SECURITY.md"

@'
# Аналіз і майбутні модулі

- ToxicRadar (теплова карта, кластери)  
- NetworkGraph (зв’язки впливу)  
- SentimentMatrix (тональність, баланс)  
- Автоконтрнаративи (бібліотека відповідей)
'@ | Set-Content -Encoding UTF8 "$base\docs\ANALYSIS.md"

Write-Host "[OK] Skeleton created at: $base"
