# CHECHA_CORE Repo Hygiene Bundle (2025)
Date: 2025-10-19 09:12:37
Tag: IDE-ENV-2025-10

Includes:
- .editorconfig — enforce UTF-8, CRLF, final newline, trimming.
- .gitattributes — normalize EOL (CRLF for ps1/psm1/psd1/md/json/yml; LF for .sh), binary patterns.
- .gitignore — ignore logs, temp, build outputs, IDE/venv, artifacts.
- README_repo_hygiene.md — how-to for editorconfig/gitattributes.
- README_gitignore.md — how-to for gitignore.

Install:
1) Place all files into D:\CHECHA_CORE\ (repo root).
2) Renormalize and commit:
   git add --renormalize .
   git commit -m "apply repo hygiene bundle (IDE-ENV-2025-10)"
