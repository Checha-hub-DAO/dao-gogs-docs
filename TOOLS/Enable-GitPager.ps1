# Enable-GitPager.ps1
Write-Host "[INFO] Вмикаю pager для Git..."
git config --global --unset pager.log
git config --global --unset pager.diff
git config --global --unset pager.show
git config --global --unset pager.branch
git config --global --unset pager.tag
Write-Host "[OK] Git pager увімкнено (повернено стандартні налаштування)."

Write-Host "[INFO] Вмикаю pager для GitHub CLI (gh)..."
gh config set pager less
Write-Host "[OK] gh pager увімкнено."

Write-Host "[DONE] Тепер git/gh знову використовують less."
