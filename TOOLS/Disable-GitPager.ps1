# Disable-GitPager.ps1
Write-Host "[INFO] Вимикаю pager для Git..."
git config --global pager.log false
git config --global pager.diff false
git config --global pager.show false
git config --global pager.branch false
git config --global pager.tag false
Write-Host "[OK] Git pager вимкнено."

Write-Host "[INFO] Вимикаю pager для GitHub CLI (gh)..."
gh config set pager ""
Write-Host "[OK] gh pager вимкнено."

Write-Host "[DONE] Тепер git/gh не відкриватимуть less."
Write-Host "      Для довгих логів використовуй: git log > file.txt"
