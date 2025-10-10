param(
  [string]$Root = 'D:\CHECHA_CORE',
  [switch]$DryRun
)

#!/bin/sh
# Pre-push hook: block direct pushes to main; allow tags and whitelisted branches.
# Logs to .git/pre-push-debug.log for troubleshooting.

blocked="refs/heads/main"
log=".git/pre-push-debug.log"

# start fresh log
: > "$log"
echo "== pre-push $(date -u +'%Y-%m-%dT%H:%M:%SZ') ==" >> "$log"
echo "blocked=$blocked" >> "$log"

# Whitelist: release/*, hotfix/*, infra/*, dev/*
is_whitelisted() {
  ref="$1"
  case "$ref" in
    refs/heads/release/*|refs/heads/hotfix/*|refs/heads/infra/*|refs/heads/dev/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Read stdin: <local_ref> <local_sha> <remote_ref> <remote_sha>
while read local_ref local_sha remote_ref remote_sha
do
  echo "line: local_ref=$local_ref local_sha=$local_sha remote_ref=$remote_ref remote_sha=$remote_sha" >> "$log"

  # allow tags always
  case "$local_ref" in refs/tags/*) echo " -> allow: local tag"  >> "$log"; continue ;; esac
  case "$remote_ref" in refs/tags/*) echo " -> allow: remote tag" >> "$log"; continue ;; esac

  # prefer remote_ref when present
  ref_to_check="$remote_ref"
  if [ -z "$ref_to_check" ]; then
    ref_to_check="$local_ref"
  fi
  echo " ref_to_check=$ref_to_check" >> "$log"

  # whitelist passes
  if is_whitelisted "$ref_to_check" || is_whitelisted "$local_ref"; then
    echo " -> allow: whitelisted ($ref_to_check / $local_ref)" >> "$log"
    continue
  fi

  # block main updates
  if [ "$ref_to_check" = "$blocked" ] || [ "$local_ref" = "$blocked" ]; then
    echo " -> BLOCK: main update detected (ref_to_check=$ref_to_check local_ref=$local_ref)" >> "$log"
    echo "[BLOCK] Direct push to 'main' is disallowed. Create a feature branch & PR."
    exit 1
  fi

  echo " -> allow: not-main ref" >> "$log"
done

echo "OK: no main updates in this push" >> "$log"
exit 0

$hook = ".githooks/pre-commit"
$pc = @'
#!/bin/sh
# Pre-commit with logging: hygiene + optional formatters.
# Log file: .git/pre-commit-debug.log

LOG=".git/pre-commit-debug.log"
: > "$LOG"
echo "== pre-commit $(date -u +'%Y-%m-%dT%H:%M:%SZ') ==" >> "$LOG"

MAX_SIZE=$((5*1024*1024))  # 5 MB
FAILED=0

# collect staged (Added/Modified/Renamed-to)
STAGED=$(git diff --cached --name-only --diff-filter=AMR)
[ -z "$STAGED" ] && { echo "no staged files" >> "$LOG"; exit 0; }

is_binary_ext() {
  case "$1" in
    *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.ico|*.zip|*.7z|*.rar|*.pdf|*.exe|*.dll|*.so|*.dylib|*.mp4|*.mp3) return 0 ;;
    *) return 1 ;;
  esac
}

has_secret() {
  # quick heuristics
  grep -E -q 'AWS_(ACCESS|SECRET)_KEY|AKIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36,}|-----BEGIN( RSA)? PRIVATE KEY-----' "$1"
}

# detect optional formatters
HAS_PRETTIER=0; command -v prettier >/dev/null 2>&1 && HAS_PRETTIER=1
HAS_BLACK=0;    command -v black    >/dev/null 2>&1 && HAS_BLACK=1

echo "staged files:" >> "$LOG"
echo "$STAGED" | sed 's/^/ - /' >> "$LOG"

for f in $STAGED; do
  # skip missing (deleted/moved away)
  [ ! -e "$f" ] && { echo "skip missing: $f" >> "$LOG"; continue; }

  echo "--- file: $f" >> "$LOG"

  # 1) size guard
  if [ -f "$f" ]; then
    sz=$(wc -c <"$f" 2>/dev/null)
    if [ -n "$sz" ] && [ "$sz" -gt "$MAX_SIZE" ]; then
      echo "[BLOCK] too large ($sz bytes)" >> "$LOG"
      echo "[BLOCK] File too large (>5MB): $f ($sz bytes)"
      FAILED=1; continue
    fi
  fi

  # 2) binary by extension
  if is_binary_ext "$f"; then
    echo "[BLOCK] binary by ext" >> "$LOG"
    echo "[BLOCK] Binary file not allowed in commit: $f"
    FAILED=1; continue
  fi

  # 3) for text-ish: secrets + trim trailing spaces (normalize CRLF->LF)
  if file "$f" | grep -qiE 'text|unicode'; then
    if has_secret "$f"; then
      echo "[BLOCK] secret heuristic matched" >> "$LOG"
      echo "[BLOCK] Potential secret detected in: $f"
      FAILED=1
      continue
    fi

    tmp="$f.__precommit_tmp__"
    # normalize CRLF->LF and trim trailing spaces
    tr -d '\r' <"$f" | sed -E 's/[[:space:]]+$//' > "$tmp"
    if ! cmp -s "$f" "$tmp"; then
      mv "$tmp" "$f"
      git add "$f"
      echo "[fix] trimmed trailing spaces + LF normalized" >> "$LOG"
    else
      rm -f "$tmp"
      echo "no trim needed" >> "$LOG"
    fi
  else
    echo "non-text (by 'file' tool), skipping trim/scan" >> "$LOG"
  fi
done

# 4) optional formatting
if [ $HAS_PRETTIER -eq 1 ]; then
  PRETTIER_TARGETS=$(echo "$STAGED" | grep -E '\.(js|ts|jsx|tsx|json|md|yaml|yml|css|scss)$' || true)
  if [ -n "$PRETTIER_TARGETS" ]; then
    npx --yes prettier --loglevel warn --write $PRETTIER_TARGETS >> "$LOG" 2>&1
    git add $PRETTIER_TARGETS
    echo "[fmt] prettier applied" >> "$LOG"
  else
    echo "prettier: no targets" >> "$LOG"
  fi
else
  echo "prettier not found" >> "$LOG"
fi

if [ $HAS_BLACK -eq 1 ]; then
  PY_TARGETS=$(echo "$STAGED" | grep -E '\.py$' || true)
  if [ -n "$PY_TARGETS" ]; then
    black -q $PY_TARGETS >> "$LOG" 2>&1
    git add $PY_TARGETS
    echo "[fmt] black applied" >> "$LOG"
  else
    echo "black: no targets" >> "$LOG"
  fi
else
  echo "black not found" >> "$LOG"
fi

if [ $FAILED -ne 0 ]; then
  echo "[FAIL] see $LOG" >> "$LOG"
  echo ""
  echo "Pre-commit checks failed. See $LOG for details."
  echo "Fix issues or commit with --no-verify (NOT recommended)."
  exit 1
fi

echo "[OK] pre-commit passed" >> "$LOG"
exit 0
'@

($pc -replace "`r`n","`n") | Set-Content -Path $hook -Encoding Ascii

# ---------- install to all repos ----------
$repos = Get-ChildItem -Path $Root -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName '.git') }

if (-not $repos) { Write-Host "Репозиторії не знайдено в $Root" -ForegroundColor Yellow; exit 0 }

foreach($r in $repos){
  $repo = $r.FullName
  Write-Host "`n=== $repo ===" -ForegroundColor Green
  if ($DryRun) {
    Write-Host "• DRY-RUN: set core.hooksPath=.githooks; install pre-commit & pre-push"
    continue
  }
  $githooks = Join-Path $repo '.githooks'
  New-Item -ItemType Directory -Force $githooks | Out-Null

  # write hooks as ASCII/LF
  [System.IO.File]::WriteAllText((Join-Path $githooks 'pre-push'),   $prePush,   [System.Text.Encoding]::ASCII)
  [System.IO.File]::WriteAllText((Join-Path $githooks 'pre-commit'), $preCommit, [System.Text.Encoding]::ASCII)

  Push-Location $repo
  git config core.hooksPath .githooks
  Pop-Location

  Write-Host "• hooksPath -> .githooks"
  Write-Host "• installed: pre-commit, pre-push"
}
Write-Host "`nDone." -ForegroundColor Cyan
