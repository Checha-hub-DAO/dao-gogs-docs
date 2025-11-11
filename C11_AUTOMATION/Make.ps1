# =====================================================================
# SCRIPT: Make.ps1  (CHECHA CORE)
# DESC  : Легкий "make" для G35 та DevTools
# NOTE  : Без param/CmdletBinding на рівні файлу. Усе всередині function make.
# =====================================================================

function make {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$target,
    [string]$arg
  )

  # ---- Базові шляхи (за потреби змінюй один раз тут) ----------------
  $ROOT       = 'D:\CHECHA_CORE'
  $TOOLS      = Join-Path $ROOT 'TOOLS'
  $AUTO_DIR   = Join-Path $ROOT 'C11_AUTOMATION'
  $AUTO_TOOLS = Join-Path $AUTO_DIR 'TOOLS'
  $TMP_DIR    = Join-Path $ROOT 'TMP'
  $SERIES     = 'Pravo_i_Sovist'   # серія за замовчуванням

  switch ($target) {

    # ====================== G35 RELEASE ================================
    'g35:release-md' {
      pwsh -NoProfile -File (Join-Path $TOOLS 'Invoke-G35Release.ps1') `
        -SeriesName $SERIES -Log -GitCommit
    }

    'g35:release-md:full' {
      pwsh -NoProfile -File (Join-Path $TOOLS 'Invoke-G35Release.ps1') `
        -SeriesName $SERIES `
        -UseOrder -UseHeaderFooter -FrontMatter -DemoteH1 `
        -Log -GitCommit
    }

    'g35:release-md@' {
      if (-not $arg) { Write-Host "Usage: make g35:release-md@ <SeriesName>" -ForegroundColor Yellow; break }
      pwsh -NoProfile -File (Join-Path $TOOLS 'Invoke-G35Release.ps1') `
        -SeriesName $arg -Log -GitCommit
    }

    # ======================= G35 DIGEST ================================
    'g35:digest' {
      pwsh -NoProfile -File (Join-Path $AUTO_TOOLS 'Build-G35Digest.ps1') `
        -SeriesName $SERIES -OutputDate -OutputSuffix "_G35" `
        -StripFrontMatter -Toc -Zip -Log
    }

    'g35:digest:open' {
      pwsh -NoProfile -File (Join-Path $AUTO_TOOLS 'Build-G35Digest.ps1') `
        -SeriesName $SERIES -OutputDate -OutputSuffix "_G35" `
        -StripFrontMatter -Toc -Zip -Log -Open
    }

    'g35:digest:git' {
      pwsh -NoProfile -File (Join-Path $AUTO_TOOLS 'Build-G35Digest.ps1') `
        -SeriesName $SERIES -OutputDate -OutputSuffix "_G35" `
        -StripFrontMatter -Toc -Zip -Log -GitCommit -Push
    }

    'g35:digest@' {
      if (-not $arg) { Write-Host "Usage: make g35:digest@ <SeriesName>" -ForegroundColor Yellow; break }
      pwsh -NoProfile -File (Join-Path $AUTO_TOOLS 'Build-G35Digest.ps1') `
        -SeriesName $arg -OutputDate -OutputSuffix "_G35" `
        -StripFrontMatter -Toc -Zip -Log
    }

    # ======================= DevTools =================================
    'dev:lint'         { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target lint         -Scope $ROOT }
    'dev:lint:changed' { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target lint         -Scope $ROOT -ChangedOnly }
    'dev:fmt'          { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target fmt          -Scope $ROOT }
    'dev:fmt:24h'      { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target fmt          -Scope $ROOT -SinceHours 24 }
    'dev:fix'          { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target fix          -Scope $ROOT }
    'dev:test'         { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target test         -Scope (Join-Path $ROOT 'C11_AUTOMATION') }
    'dev:manifest'     { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target manifest     -Root  $ROOT -OutDir $TMP_DIR }
    'dev:notes'        { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target release-notes -Root  $ROOT }
    'dev:notes:open'   {
      $out = Join-Path $TMP_DIR ('G35_RELEASE_NOTES_' + (Get-Date -Format 'yyyy-MM-dd') + '.md')
      pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target release-notes -Root $ROOT
      if (Test-Path $out) { Invoke-Item $out }
    }
    'dev:notes:git'    {
      $out  = Join-Path $TMP_DIR ('G35_RELEASE_NOTES_' + (Get-Date -Format 'yyyy-MM-dd') + '.md')
      $repo = $ROOT
      pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target release-notes -Root $ROOT
      if (Test-Path $out) {
        if (Get-Command git -ErrorAction SilentlyContinue) {
          git -C $repo add -- "$out"
          git -C $repo commit -m ("DevTools notes {0}" -f (Get-Date -Format 'yyyy-MM-dd')) 2>$null
          git -C $repo push 2>$null
        } else {
          Write-Warning "git not found; skipping commit"
        }
      }
    }
    'dev:summary'      { pwsh -NoProfile -File (Join-Path $AUTO_DIR 'DevTools.ps1') -Target summary }

    # ===================== Обслуговування ==============================
    'cleanup:notes' {
      $pattern = 'G35_RELEASE_NOTES_*.md'
      $days    = 14
      if (-not (Test-Path $TMP_DIR)) { break }
      Get-ChildItem -LiteralPath $TMP_DIR -Filter $pattern -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$days) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
      Write-Host ("[OK] Old notes (> {0} days) cleaned in {1}" -f $days, $TMP_DIR) -ForegroundColor Green
    }

    # ===================== Довідка/Список ==============================
    'make:list' {
      @(
        'g35:release-md',
        'g35:release-md:full',
        'g35:release-md@ <SeriesName>',
        'g35:digest',
        'g35:digest:open',
        'g35:digest:git',
        'g35:digest@ <SeriesName>',
        'dev:lint','dev:lint:changed','dev:fmt','dev:fmt:24h','dev:fix','dev:test',
        'dev:manifest','dev:notes','dev:notes:open','dev:notes:git','dev:summary',
        'cleanup:notes'
      ) | ForEach-Object { Write-Host $_ }
    }

    'help' { make make:list }

    default {
      Write-Host ("make: Unknown target: {0}" -f $target) -ForegroundColor Red
    }
  }
}

# Якщо виконали як скрипт без параметрів — покажемо підказку
if ($MyInvocation.InvocationName -ne '.') {
  if ($args.Count -eq 0) {
    Write-Host "Use: make <target> [arg]" -ForegroundColor Cyan
    Write-Host "Try: make make:list"
  }
}
