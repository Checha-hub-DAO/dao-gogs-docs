[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$User,          # GitHub user/org
    [Parameter(Mandatory = $true)][string]$Repo,          # repo name
    [ValidateSet('ssh', 'https')][string]$Protocol = 'ssh',
    [switch]$CreateRepo,                                # створити репо на GitHub, якщо не існує
    [string]$DefaultBranch = 'reports',
    [switch]$PatchGitignore,                            # авто-додати виняток для C11/
    [string]$Token                                      # PAT для HTTPS або API (якщо нема gh)
)

function Invoke-Git { param([string]$Args) & git $Args.Split(' ') 2>&1 }
function Fail($msg) { Write-Error $msg; exit 1 }

# 1) Визначити корінь git
$root = (Invoke-Git 'rev-parse --show-toplevel'); if ($LASTEXITCODE -ne 0) { Fail "Не git-репозиторій." }
$root = $root[-1]
Set-Location $root

# 2) Побудувати URL
if ($Protocol -eq 'ssh') { $url = "git@github.com:$User/$Repo.git" }
else { $url = "https://github.com/$User/$Repo.git" }

# 3) Перевірити/встановити origin
$cur = Invoke-Git 'remote get-url origin'
if ($LASTEXITCODE -ne 0) {
    Write-Host "[INFO] origin нема — додаю: $url"
    Invoke-Git "remote add origin $url" | Out-Null
}
elseif ($cur[-1] -match 'YOUR_USER|YOUR_REPO|<твій-юзер>|<твій-репо>') {
    Write-Host "[INFO] origin placeholder → оновлюю на: $url"
    Invoke-Git "remote set-url origin $url" | Out-Null
}
else {
    Write-Host "[OK] origin існує: $($cur[-1])"
}

# 4) Перевірити доступність репо
Invoke-Git 'ls-remote origin' | Out-Null
if ($LASTEXITCODE -ne 0) {
    if (-not $CreateRepo) { Fail "Репозиторій $User/$Repo не існує або немає доступу. Запусти зі -CreateRepo або задай коректний URL." }

    Write-Host "[INFO] Репозиторій не знайдено — створюю…"

    # 4a) Якщо є gh → найпростіше
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $vis = 'private'
        gh repo create "$User/$Repo" --$vis --source "$root" --remote origin --push --branch "$DefaultBranch" --disable-wiki --confirm
        if ($LASTEXITCODE -ne 0) { Fail "gh repo create не вдалось." }
    }
    else {
        # 4b) Через API з PAT (user-scoped). Якщо Token не передано — пробуємо з env:GITHUB_TOKEN
        if (-not $Token) { $Token = $env:GITHUB_TOKEN }
        if (-not $Token) { Fail "Нема gh і PAT. Дай -Token <PAT> або встанови gh." }

        $body = @{ name = $Repo; private = $true } | ConvertTo-Json
        $resp = Invoke-RestMethod -Method Post -Uri "https://api.github.com/user/repos" -Headers @{Authorization = "Bearer $Token"; 'User-Agent' = "checha-setup" } -Body $body -ContentType 'application/json'
        if (-not $resp.clone_url) { Fail "API створення репо не повернуло clone_url." }

        # Після створення — сетимо URL (на випадок, якщо був інший)
        Invoke-Git "remote set-url origin $url" | Out-Null
        # Створюємо upstream гілку
        Invoke-Git "push -u origin $DefaultBranch"
        if ($LASTEXITCODE -ne 0) { Fail "push не вдалось після створення репо." }
    }
}
else {
    Write-Host "[OK] origin доступний."
}

# 5) (Опційно) Полагодити .gitignore для C11
if ($PatchGitignore) {
    $gi = Join-Path $root '.gitignore'
    if (Test-Path $gi) {
        $txt = Get-Content $gi -Raw
        if ($txt -match '(^|\n)\s*C11/?\s*(\n|$)' -and $txt -notmatch '!C11/') {
            Add-Content $gi "`n!C11/`n!C11/BTD_Integration_Map.md"
            Write-Host "[OK] Додав винятки до .gitignore для C11/"
            Invoke-Git 'add .gitignore' | Out-Null
        }
    }
}

# 6) Пуш поточної гілки (якщо не має upstream)
$branch = (Invoke-Git 'rev-parse --abbrev-ref HEAD')[-1]
$hasUpstream = (Invoke-Git "rev-parse --abbrev-ref --symbolic-full-name @{u}")
if ($LASTEXITCODE -ne 0) {
    Write-Host "[INFO] Нема upstream → пушу з -u"
    Invoke-Git "push -u origin $branch"
}
else {
    Write-Host "[INFO] Upstream є → звичайний push"
    Invoke-Git "push"
}
if ($LASTEXITCODE -ne 0) { Fail "push не вдався. Перевір доступ/правильність URL." }

Write-Host "[DONE] origin = $url; branch = $branch → OK"

