# CHECHA_CORE Repo Hygiene (2025)
Date: 2025-10-19 09:07:33

Included:
- `.editorconfig` — consistent UTF-8, CRLF, final newline, trimming; specific rules for ps1/psm1/psd1, md, json/yaml, sh.
- `.gitattributes` — CRLF for PowerShell/Markdown/JSON/YAML, LF for `.sh`; binaries excluded from EOL normalization.

Usage:
1) Place both files at repo root: `D:\CHECHA_CORE\`
2) Renormalize repository:
   ```bash
   git add --renormalize .
   git commit -m "apply editorconfig + gitattributes (IDE-ENV-2025-10)"
   ```
