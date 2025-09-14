# CHECKLIST — Git & Releases
1) cd D:\CHECHA_CORE
2) git remote -v  (SSH URL → owner/checha-core)
3) git add -A && git commit -m "<msg>" && git push
4) Rebuild CHECKSUMS: C11\SHIELD4_ODESA\Release\CHECKSUMS.txt із фактичних *.zip
5) Validate: C11\tools\Validate-Releases.ps1 -Module SHIELD4_ODESA -Root D:\CHECHA_CORE -Strict
6) (Plan B) Пряма перевірка хешів, якщо треба
7) Release G43: gh release create g43-iteta-v1.0 <ZIP>
8) Control: git ls-remote origin main; Get-ScheduledTaskInfo Checha-Coord-Weekly
