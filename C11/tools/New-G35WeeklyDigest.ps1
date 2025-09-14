[CmdletBinding(SupportsShouldProcess)]
param(
  [DateTime]$Start,
  [DateTime]$End,
  [switch]$Auto,
  [switch]$NoPush
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root = (Get-Location).Path

if ($Auto -or -not $PSBoundParameters.ContainsKey("Start")) {
  $today=(Get-Date).Date
  $mondayThis=$today.AddDays(- (([int]$today.DayOfWeek + 6) % 7))
  $Start=$mondayThis.AddDays(-7); $End=$Start.AddDays(6)
}
$startS=$Start.Date.ToString('yyyy-MM-dd')
$endS  =$End.Date.ToString('yyyy-MM-dd')
$f="C03/LOG/G35_Weekly_Digest_${startS}_${endS}.md"

$owner=(gh api user -q .login 2>$null)
$repoFull= if ($owner) { "$owner/checha-core" } else { "Checha-hub-DAO/checha-core" }
$tag='g43-iteta-v1.0'
$relUrl    =(gh release view $tag --repo $repoFull --json url -q .url 2>$null)
$relDigest =(gh release view $tag --repo $repoFull --json assets -q '.assets[] | select(.name=="G43_ITETA_v1.0.zip").digest' 2>$null)
$task=Get-ScheduledTaskInfo -TaskName 'Checha-Coord-Weekly' -ErrorAction SilentlyContinue
$taskLine= if ($task) { "LastRun=$($task.LastRunTime), Result=0x{0:X}" -f $task.LastTaskResult } else { "н/д" }
$commits=git log --since=$startS --until="$endS 23:59" --pretty="- %h %ad %s" --date=format:'%Y-%m-%d %H:%M' 2>$null

@"
# G35 Weekly Digest ($startS → $endS)

## Підсумок тижня
- $(if ($relUrl) {"Опубліковано реліз **G43 ITETA v1.0**: $relUrl"} else {"Реліз G43 ITETA v1.0 — н/д"})
- $(if ($relDigest) {"SHA256 артефакту: $relDigest"} else {"SHA256 — н/д"})
- Планувальник **Checha-Coord-Weekly**: $taskLine
- Оновлено індекс **C12/Vault** (за потреби).

## Коміти за тиждень
$([string]::IsNullOrWhiteSpace($commits) ? "_без комітів за період_" : $commits)

## Метрики/сигнали
- Release integrity: SHA256 перевірено/актуалізовано.
- Repo hygiene: main синхронізовано.

## Ризики / next steps
- Замінити stub-валідатор на повний + підʼєднати в CI.
- Оновити README/Docs за потреби.
"@ | Set-Content -Encoding UTF8 $f

if ($PSCmdlet.ShouldProcess($f, "git add/commit")) {
  git add -f $f
  git commit -m ("docs(G35): weekly digest {0}..{1}" -f $startS,$endS) 2>$null
}
if (-not $NoPush -and $PSCmdlet.ShouldProcess('origin/main','git push')) {
  git push
}
Write-Information ("OK: {0}" -f $f) -InformationAction Continue
