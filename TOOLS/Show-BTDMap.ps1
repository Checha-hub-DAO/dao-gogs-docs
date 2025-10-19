function Show-BTDMap {
    <#
    .SYNOPSIS
      Виводить схему інтеграції BTD 1.0 у CHECHA_CORE (без here-strings).
    .DESCRIPTION
      Режими: (без параметрів) міні-ASCII, -Full, -Mermaid. Додатково: -Check, -RepoRoot, -OutFile, -NoColor.
    #>

    [CmdletBinding(DefaultParameterSetName = 'AsciiMini')]
    param(
        [Parameter(ParameterSetName = 'AsciiFull')]
        [switch]$Full,

        [Parameter(ParameterSetName = 'Mermaid')]
        [switch]$Mermaid,

        [switch]$Check,
        [string]$RepoRoot = 'D:\CHECHA_CORE',
        [string]$OutFile,
        [switch]$NoColor
    )

    function Test-Node {
        param([string]$Rel)
        Test-Path -LiteralPath (Join-Path -Path $RepoRoot -ChildPath $Rel)
    }
    function Mark {
        param([string]$Label, [bool]$Exists)
        if ($Exists) { "$Label [OK]" } else { "$Label [MISSING]" }
    }
    function MarkEmoji {
        param([string]$Label, [bool]$Exists)
        if ($Exists) { "$Label ✅" } else { "$Label ❌" }
    }
    function OutText {
        param([string]$Text)
        if ($OutFile) { $Text | Set-Content -LiteralPath $OutFile -Encoding UTF8; Write-Host "[OK] Saved to $OutFile" }
        else { if ($NoColor) { Write-Host $Text } else { Write-Host $Text -ForegroundColor Cyan } }
    }

    $exists = @{
        INBOX   = if ($Check) { Test-Node 'INBOX' }         else { $true }
        C12     = if ($Check) { Test-Node 'C12_KNOWLEDGE' } else { $true }
        C11     = if ($Check) { Test-Node 'C11' }           else { $true }
        C03     = if ($Check) { Test-Node 'C03_LOG' }       else { $true }
        REPORTS = if ($Check) { Test-Node 'REPORTS' }       else { $true }
        TOOLS   = if ($Check) { Test-Node 'TOOLS' }         else { $true }
    }

    if ($Mermaid) {
        $nINBOX = MarkEmoji '📥 INBOX\nВхідний буфер / Артефакти'              $exists.INBOX
        $nC12 = MarkEmoji '📚 C12_KNOWLEDGE\nMD_INBOX / MD_AUDIT / ARCHIVE'  $exists.C12
        $nC11 = MarkEmoji '📘 C11 — BTD 1.0\nMANIFEST / CHECKSUMS / INDEX'   $exists.C11
        $nC03 = MarkEmoji '📑 C03_LOG\nЖурнал змін / AUDIT-логи'             $exists.C03
        $nRPT = MarkEmoji '📝 REPORTS\nДайджести / Чеклісти / Тести'         $exists.REPORTS
        $nTOOLS = MarkEmoji '⚙️ TOOLS\nСкрипти автоматизації'                  $exists.TOOLS

        $lines = @()
        $lines += '```mermaid'
        $lines += 'flowchart TD'
        $lines += ''
        $lines += "  INBOX[`"$nINBOX`"]"
        $lines += "  C12[`"$nC12`"]"
        $lines += "  C11[`"$nC11`"]"
        $lines += "  C03[`"$nC03`"]"
        $lines += "  RPT[`"$nRPT`"]"
        $lines += "  TOOLS[`"$nTOOLS`"]"
        $lines += ''
        $lines += '  INBOX --> C12'
        $lines += '  C12   --> C11'
        $lines += '  C11   --> RPT'
        $lines += '  C11   --> C03'
        $lines += '  TOOLS --> C11'
        $lines += '  TOOLS --> RPT'
        $lines += '  TOOLS --> INBOX'
        $lines += '  TOOLS --> C03'
        $lines += ''
        $lines += '  subgraph AUTO[🔄 Автоматизація]'
        $lines += '    GH[GitHub Actions\nbtd-weekly-digest.yml]'
        $lines += '    TS[Windows Task Scheduler]'
        $lines += '    HOOKS[Git Hooks\npre-commit / post-commit]'
        $lines += '  end'
        $lines += ''
        $lines += '  HOOKS --> C11'
        $lines += '  TS    --> TOOLS'
        $lines += '  GH    --> TOOLS'
        $lines += ''
        $lines += '  RPT --> C03'
        $lines += '  C03 --> C11'
        $lines += '  C12 --> RPT'
        $lines += '```'

        OutText -Text ($lines -join "`r`n")
        return
    }

    if ($Full) {
        $INBOX = Mark '📥 INBOX'             $exists.INBOX
        $C12 = Mark '📚 C12 KNOWLEDGE'     $exists.C12
        $C11 = Mark '📘 C11 — BTD 1.0'     $exists.C11
        $C03 = Mark '📑 C03_LOG'           $exists.C03
        $RPT = Mark '📝 REPORTS'           $exists.REPORTS
        $TOOLS = Mark '⚙ TOOLS'              $exists.TOOLS

        $l = @()
        $l += '                ┌────────────────┐'
        $l += "                │  $INBOX  │"
        $l += '                │  Вхідний буфер │'
        $l += '                └──────┬─────────┘'
        $l += '                       │'
        $l += '                       ▼'
        $l += '                ┌────────────────┐'
        $l += "                │  $C12  │"
        $l += '                │  (MD, Audit)   │'
        $l += '                └──────┬─────────┘'
        $l += '                       │'
        $l += '                       ▼'
        $l += '   ┌───────────────────────────────────────────┐'
        $l += "   │ $C11                         │"
        $l += '   │ MANIFEST / CHECKSUMS / INDEX             │'
        $l += '   └───┬────────────────────┬─────────────────┘'
        $l += '       │                    │'
        $l += '       ▼                    ▼'
        $l += '┌────────────────┐   ┌────────────────┐'
        $l += "│  $RPT  │   │  $C03  │"
        $l += '│ Дайджести/Чекл.│   │ Журнал змін    │'
        $l += '└──────┬─────────┘   └──────┬─────────┘'
        $l += '       │                    │'
        $l += '       └─────────┬──────────┘'
        $l += '                 ▼'
        $l += '         ┌────────────────┐'
        $l += "         │   $TOOLS   │"
        $l += '         │  Скрипти автом. │'
        $l += '         └──────┬─────────┘'
        $l += '                │'
        $l += '      ┌─────────┼───────────────┐'
        $l += '      ▼         ▼               ▼'
        $l += '  Git Hooks   Task Scheduler   GitHub Actions'
        $l += '  (pre/post)  (локально)       (CI/CD)'

        OutText -Text ($l -join "`r`n")
        return
    }

    # Mini ASCII
    $INBOX = Mark 'INBOX'             $exists.INBOX
    $C12 = Mark 'C12_KNOWLEDGE'     $exists.C12
    $C11 = Mark 'C11 (BTD)'         $exists.C11
    $RPT = Mark 'REPORTS'           $exists.REPORTS
    $C03 = Mark 'C03_LOG'           $exists.C03
    $TOOLS = Mark 'TOOLS'             $exists.TOOLS

    $m = @()
    $m += "$INBOX → $C12 → $C11"
    $m += '              │'
    $m += "   $RPT ←──┼──→ $C03"
    $m += '              │'
    $m += "            $TOOLS"
    $m += '    (Git Hooks / Task / CI)'

    OutText -Text ($m -join "`r`n")
}

