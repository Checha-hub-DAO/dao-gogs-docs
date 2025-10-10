# ===== Install Git pre-push hooks across CHECHA_CORE =====
# Блокує прямий push у refs/heads/main, дозволяє інші гілки та теги.
# Хук версіонується у .githooks\pre-push і підключається через core.hooksPath.

param(
  [string]$Root = 'D:\CHECHA_CORE',
  [switch]$DryRun,                    # лише показати що буде зроблено
  [string[]]$WhitelistBranches = @('refs/heads/release/*','refs/heads/hotfix/*') # дозволені патерни
)

function Write-Step($msg){ Write-Host "• $msg" -ForegroundColor Cyan }
function Matches-Whitelist($ref, $patterns){
  foreach($p in $patterns){
    $rx = '^' + ($p -replace '\*','.*') + '$'
    if($ref -match $rx){ return $true }
  }
  return $false
}

# Вміст pre-push (bash, LF, ASCII)
$hookContent = @"
#!/bin/sh
# Block direct pushes to main; allow tags and whitelisted branches.

blocked="refs/heads/main"

# Whitelist patterns (shell globs), edit as needed:
whitelist="refs/heads/release/* refs/heads/hotfix/*"

# Convert whitelist to space-separated; we'll test with case.
is_whitelisted() {
  ref="$1"
  for pat in $whitelist; do
    case "$ref" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# Read stdin: <local_ref> <local_sha> <remote_ref> <remote_sha>
while read local_ref local_sha remote_ref remote_sha
do
  # allow tags always
  case "$local_ref" in refs/tags/*) continue ;; esac
  case "$remote_ref" in refs/tags/*) continue ;; esac

  # prefer remote_ref when present
  ref_to_check="$remote_ref"
  if [ -z "$ref_to_check" ]; then ref_to_check="$local_ref"; fi

  # whitelist?
  if is_whitelisted "$ref_to_check" || is_whitelisted "$local_ref"; then
    continue
  fi

  # block main
  if [ "$ref_to_check" = "$blocked" ] || [ "$local_ref" = "$blocked" ]; then
    echo "[BLOCK] Direct push to 'main' is disallowed. Create a feature branch & PR."
    exit 1
  fi
done

exit 0
"@ -replace "`r`n","`n"

# Знайти всі git-репозиторії
$repos = Get-ChildItem -Path $Root -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName '.git') }

if(-not $repos){ Write-Host "Репозиторії не знайдено в $Root" -ForegroundColor Yellow; exit 0 }

foreach($repo in $repos){
  $path = $repo.FullName
  Write-Host "`n=== $path ===" -ForegroundColor Green

  if($DryRun){
    Write-Step "DRY-RUN: поставимо core.hooksPath=.githooks і створимо .githooks\pre-push"
    continue
  }

  Push-Location $path
  try{
    # переконатися, що є гілка/історія (інакше git config зчитується, але нам просто потрібна структура)
    $githooks = Join-Path $path '.githooks'
    New-Item -ItemType Directory -Force $githooks | Out-Null

    # записати хук (ASCII, LF)
    $hookPath = Join-Path $githooks 'pre-push'
    [System.IO.File]::WriteAllText($hookPath, $hookContent, [System.Text.Encoding]::ASCII)

    # встановити core.hooksPath
    git config core.hooksPath .githooks

    # показати підсумок
    Write-Step "hooksPath -> $(git config core.hooksPath)"
    Write-Step "pre-push -> .githooks\pre-push (len: $((Get-Item $hookPath).Length) bytes)"
  } finally {
    Pop-Location
  }
}

Write-Host "`nГотово. Хук встановлено у всіх знайдених репозиторіях." -ForegroundColor Cyan
