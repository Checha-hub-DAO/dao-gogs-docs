# CHECHA_CORE .gitignore (2025)
Date: 2025-10-19 09:11:13

Covers:
- Temp files, logs, .bak versions (PowerShell restore/repair sessions)
- Build & report artifacts (`/out`, `/reports`, `/C03_LOG/*`)
- IDE & environment folders (`.vscode`, `.idea`, `.venv`, etc.)
- Security and binary files (`*.exe`, `*.pfx`, `*.zip`)
- Auto-generated analytics and digest outputs

Usage:
1) Place `.gitignore` at `D:\CHECHA_CORE\`
2) Normalize repository:
   ```bash
   git add --renormalize .
   git commit -m "apply gitignore (IDE-ENV-2025-10)"
   ```
