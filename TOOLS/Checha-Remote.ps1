[CmdletBinding()]
param(
  [string]$RepoRoot,                        # Якщо не задано — спробує визначити через git
  [string]$User = $env:CHECHA_GH_USER,      # GitHub user/org
  [string]$Repo = $env:CHECHA_GH_REPO,      # repo name
  [ValidateSet('ssh','https')][string]$Protocol = 'ssh',
  [switch]$CreateRepo,                      # Створити репо, якщо недоступне
  [string]$DefaultBranch = '',              # Якщо пусто — візьме поточну
  [switch]$PatchGitignore,                  # Додати винятки для C11/
  [string]$Token = $env:GITHUB_TOKEN        # PAT для HTTPS або API, якщо нема gh
)

function Die($m){ Write-Error $m; exit 1 }
function Git([string]$a){ & git $a.Split(' ') 2>&1 }

# 0) Знайти корінь репо
if ($RepoRoot -and (Test-Path $RepoRoot)) {
  $root = (Resolve-Path $RepoRoot).Path
} else {
  $root = (Git 'rev-parse --show-toplevel')
  if ($LASTEXITCODE -ne 0 -or -not $root) { Die "Не git-репозиторій і -RepoRoot не задано." }
  $root = $root[-1]
}
Set-Location $root

# 1) Перевірки параметрів
if (-not $User -or -not $Repo) { Die "Задай -User та -Repo або встанови CHECHA_GH_USER / CHECHA_GH_REPO." }

# 2) Визначити гілку
$branch = if ($DefaultBranch) { $DefaultBranch } else { (Git 'rev-parse --abbrev-ref HEAD')[-1] }
if (-not $branch -or $branch -eq 'HEAD') { Die "Не вдалося визначити гілку. Створи/активуй гілку локально." }

# 3) Зібрати URL
$url = if ($Protocol -eq 'ssh') { "git@github.com:$User/$Repo.git" } else { "https://github.com/$User/$Repo.git" }

# 4) Налаштувати origin
$cur = Git 'remote get-url origin'
if ($LASTEXITCODE -ne 0) {
  Write-Host "[INFO] origin нема — додаю: $url"
  Git "remote add origin $url" | Out-Null
} else {
  $cur = $cur[-1]
  if ($cur -ne $url -or $cur -match 'YOUR_USER|YOUR_REPO|<твій-юзер>|<твій-репо>') {
    Write-Host "[INFO] origin: $cur → $url"
    Git "remote set-url origin $url" | Out-Null
  } else {
    Write-Host "[OK] origin вже налаштований: $url"
  }
}

# 5) Перевірити доступність репо
Git 'ls-remote origin' | Out-Null
if ($LASTEXITCODE -ne 0) {
  if (-not $CreateRepo) { Die "Репозиторій $User/$Repo недоступний або не існує. Додай -CreateRepo або виправ URL/доступ." }
  Write-Host "[INFO] Репозиторій відсутній — створюю…"

  if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh repo create "$User/$Repo" --private --source "$root" --remote origin --push --disable-wiki --confirm

    if ($LASTEXITCODE -ne 0) { Die "gh repo create не вдалось." }
  } else {
    if (-not $Token) { Die "Нема gh і PAT. Задай -Token або env:GITHUB_TOKEN." }
    $body = @{ name=$Repo; private=$true } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method Post -Uri "https://api.github.com/user/repos" -Headers @{Authorization="Bearer $Token"; 'User-Agent'="checha-remote"} -Body $body -ContentType 'application/json'
    if (-not $resp.clone_url) { Die "API створення репо не повернуло clone_url." }
    # Після створення — сетимо URL (на випадок, якщо був інший) та пушимо
    Git "remote set-url origin $url" | Out-Null
    Git "push -u origin $branch" | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "push не вдався після створення репо." }
  }
} else {
  Write-Host "[OK] origin доступний."
}

# 6) (Опційно) .gitignore для C11/
if ($PatchGitignore) {
  $gi = Join-Path $root '.gitignore'
  if (Test-Path $gi) {
    $txt = Get-Content $gi -Raw
    $changed = $false
    if ($txt -match '(^|\n)\s*C11/?\s*(\n|$)' -and $txt -notmatch '!C11/') {
      Add-Content $gi "`n!C11/`n!C11/BTD_Integration_Map.md"
      $changed = $true
      Write-Host "[OK] Додав винятки до .gitignore для C11/"
    }
    if ($changed) { Git 'add .gitignore' | Out-Null }
  }
}

# 7) Пуш (створити upstream, якщо нема)
Git "rev-parse --abbrev-ref --symbolic-full-name @{u}" | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "[INFO] Нема upstream → push -u origin $branch"
  Git "push -u origin $branch"
} else {
  Write-Host "[INFO] Upstream вже є → звичайний push"
  Git "push"
}
if ($LASTEXITCODE -ne 0) { Die "push не вдався. Перевір доступ або URL." }

Write-Host "[DONE] origin = $url; branch = $branch → OK"
