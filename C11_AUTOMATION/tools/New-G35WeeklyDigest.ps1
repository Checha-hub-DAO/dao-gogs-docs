[CmdletBinding(SupportsShouldProcess)]
param(
  [DateTime]$Start,
  [DateTime]$End,
  [switch]$Auto,
  [switch]$NoPush,
  [switch]$NoCommit
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Dir([string]$Path) {
  $d = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function Try-GH { param([scriptblock]$Expr) try { & $Expr } catch { $null } }

# Обчислення діапазону дат
if ($Auto -or -not $PSBoundParameters.ContainsKey('Start')) {
  $today=(Get-Date).Date
  $mondayThis=$today.AddDays(- (([int]$today.DayOfWeek + 6) % 7))
  $Start=$mondayThis.AddDays(-7); $End=$Start.AddDays(6)
}
$startS = $Start.Date.ToString('yyyy-MM-dd')
$endS   = $End.Date.ToString('yyyy-MM-dd')
$file   = "C03/LOG/G35_Weekly_Digest_${startS}_${endS}.md"
Ensure-Dir $file

# Основна логіка з «мʼяким» фолбеком
$relUrl    = $null
$relDigest = $null
$taskLine  = 'н/д'
$commits   = $null

try {
  $repoFull = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else {
    $o = Try-GH { gh api user -q .login }; if ($o) { "$o/checha-core" } else { "Checha-hub-DAO/checha-core" }
  }

  $tag       = 'g43-iteta-v1.0'
  $relUrl    = Try-GH { gh release view $tag --repo $repoFull --json url -q .url }
  $relDigest = Try-GH { gh release view $tag --repo $repoFull --json assets -q '.assets[] | select(.name=="G43_ITETA_v1.0.zip").digest' }

  $task = Get-ScheduledTaskInfo -TaskName 'Checha-Coord-Weekly' -ErrorAction SilentlyContinue
  if ($task) { $taskLine = ('LastRun={0}, Result=0x{1:X}' -f $task.LastRunTime,$task.LastTaskResult) }

  $commits = git log --since=$startS --until="$endS 23:59" --pretty="- %h %ad %s" --date=format:'%Y-%m-%d %H:%M' 2>$null
}
catch {
  # ігноруємо, все одно згенеруємо файл
}

# Формуємо контент (мінімальний — навіть якщо все н/д)
$content = @"
# G35 Weekly Digest ($startS → $endS)

## Підсумок тижня
- $(if ($relUrl) {"Опубліковано реліз **G43 ITETA v1.0**: $relUrl"} else {"Реліз G43 ITETA v1.0 — н/д"})
- $(if ($relDigest) {"SHA256 артефакту: $relDigest"} else {"SHA256 — н/д"})
- Планувальник **Checha-Coord-Weekly**: $taskLine

## Коміти за тиждень
$([string]::IsNullOrWhiteSpace($commits) ? "_без комітів за період_" : $commits)

## Метрики/сигнали
- Release integrity: якщо доступний — SHA256 підтягнуто.
- Repo hygiene: синхронізація main.

## Ризики / next steps
- Розширити валідатор релізів.
- Оновити README/Docs за потреби.
"@

# Запис файлу завжди
Set-Content -Encoding UTF8 -LiteralPath $file -Value $content

# Для CI гарантуємо диф — додаємо штамп часу
if ($NoCommit) {
  Add-Content -Encoding UTF8 -LiteralPath $file ("`n<!-- ci-touch: {0} -->" -f (Get-Date -Format o))
}

# Локальні коміт/пуш (у CI вимкнено через -NoCommit/-NoPush)
if (-not $NoCommit -and $PSCmdlet.ShouldProcess($file,'git add/commit')) {
  git add -f -- $file
  git commit -m ("docs(G35): weekly digest {0}..{1}" -f $startS,$endS) 2>$null
}
if (-not $NoPush -and $PSCmdlet.ShouldProcess('origin/main','git push')) {
  git push
}

Write-Information ("OK: {0}" -f $file) -InformationAction Continue
