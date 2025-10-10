param(
  [string]$RepoRoot = "D:\CHECHA_CORE",
  [string]$Branch   = "reports",
  [switch]$OpenWeb
)

function Die($msg){ Write-Host "[ERR] $msg" -ForegroundColor Red; exit 1 }

# 0) Перевіримо, що repo існує
if (!(Test-Path -LiteralPath $RepoRoot)) { Die "RepoRoot не знайдено: $RepoRoot" }
Set-Location $RepoRoot

# 1) Перевіримо, що тут git-репозиторій
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Die "Тека не є git-репозиторієм: $RepoRoot" }

# 2) Перемкнемося/створимо гілку, якщо потрібно
$cur = git rev-parse --abbrev-ref HEAD
if ($cur -ne $Branch) {
  git show-ref --verify --quiet "refs/heads/$Branch"
  if ($LASTEXITCODE -eq 0) { git checkout $Branch } else { git checkout -b $Branch }
}

# 3) Гарантуємо наявність C11
New-Item -ItemType Directory -Force -Path ".\C11" | Out-Null

# 4) Контент README
$readme = @"
# 🚀 Корабель CHECHA

Це головний README для секції **C11**.  
Він описує Корабель як систему навігації, карти та режими.

---

## 🧭 Навігація
- Орієнтири: CHECHA_CORE (D:\CHECHA_CORE), GitHub (dao-gogs-core / -docs-)
- Лог: REPORTS/, CHECKLIST, CHECKSUMS
- Точка входу: C11 (Knowledge Integration Hub)

---

## 🗺 Карти
- **BTD Integration Map (Mermaid)** — головна карта взаємодії модулів.
- **C11/BTD 1.0/** — базова бібліотека технічних документів.
- **SHIELD4_ODESA/** — стратегічна зона впровадження.
- Всі карти — тільки Markdown, без ZIP-архівів.

---

## ⚙️ Режими
- **Робочий** — щоденна інтеграція, коміти, аналітика.
- **Стратегічний** — створення системних планів і дорожніх карт.
- **Творчий** — візуалізація, метафори, символи, міфологія.

---

## 🧩 Модулі
- **C11** — ядро інтеграції знань.
- **BTD** — бібліотека технічних документів v1.0.
- **SHIELD** — захисні ініціативи (Щит-1..Щит-4).
- **DAO-GOGS** — глобальна операційна система свідомих.

---

## 👥 Екіпаж
- **Сергій (С.Ч.)** — капітан, архітектор, стратег.
- **ШІ-навігатор** — карта, аналітика, автоматизація.

---

## 📜 Маніфест
Мета Корабля CHECHA — інтегрувати знання, структури й символи,  
перетворюючи хаос у впорядковану систему.  

- Ми рухаємося крізь океан інформації.  
- Наші карти — знання й аналітика.  
- Наш курс — свідомість і розвиток.  

**С.Ч.**
"@

# 5) Запис README
$readme | Set-Content -LiteralPath ".\C11\README.md" -Encoding UTF8
Write-Host "[OK] Оновлено C11\README.md" -ForegroundColor Green

# 6) Додати до git і комітнути, якщо є зміни
git add -f .\C11\README.md
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git commit -m "docs(C11): add/update CHECHA ship README"
  Write-Host "[OK] Commit створено." -ForegroundColor Green
} else {
  Write-Host "[INFO] Змін для коміту немає." -ForegroundColor Yellow
}

# 7) Пуш
git push -u origin $Branch
if ($LASTEXITCODE -ne 0) { Die "Push не вдався. Перевір origin/доступ." }
Write-Host "[OK] Push → origin/$Branch" -ForegroundColor Green

# 8) Статус
git status

# 9) Відкрити GitHub
if ($OpenWeb) {
  try { gh browse } catch { Write-Host "[WARN] gh недоступний або не налаштований." -ForegroundColor Yellow }
}
