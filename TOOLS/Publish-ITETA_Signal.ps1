[CmdletBinding(SupportsShouldProcess)]
param(
[Parameter(Mandatory=$true)]
  [string] $SourceDir,

  [Parameter()]
  [string] $TargetDir = 'D:\CHECHA_CORE\C07_ANALYTICS\ITETA',

  [Parameter()]
  [string] $RepoRoot,

  [switch] $GitPush
)


function Info([string]$m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok  ([string]$m){ Write-Host "[OK]   $m" -ForegroundColor Green }
function Warn([string]$m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err ([string]$m){ Write-Host "[ERR]  $m" -ForegroundColor Red }

# 1) Вхідні файли
$signals = Get-ChildItem -LiteralPath $SourceDir -Filter 'ITETA-Signal_*.md' -File -ErrorAction SilentlyContinue
if(-not $signals){ Err "У $SourceDir не знайдено ITETA-Signal_*.md"; exit 2 }

# 2) Підготовка цілі
if(-not (Test-Path $TargetDir)){ New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }

# 3) Обробка кожного Signal
$processed = @()
foreach($sig in $signals){
  $dst = Join-Path $TargetDir $sig.Name
  if($PSCmdlet.ShouldProcess($dst, "Publish/Update")){
    # Копія у ціль (пропускаємо якщо це той самий шлях)
    if(-not ($sig.FullName -ieq $dst)){
      Copy-Item -LiteralPath $sig.FullName -Destination $dst -Force
    }

    # Читання та очищення попередніх підписів
    $content = Get-Content -LiteralPath $dst -Raw -Encoding UTF8

    # вилучаємо рядки з DigitalSignature та попередній SHA-footer (якщо був)
    $lines   = $content -split "`r?`n"
    $lines   = $lines | Where-Object { $_ -notmatch '^\s*DigitalSignature:' -and $_ -notmatch '^\s*\*\*Підпис SHA-256' }
    $content = ($lines -join "`r`n").TrimEnd()

    # SHA-256 по очищеному контенту
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    try {
      $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('X2') }) -join ''
    } finally { $sha.Dispose() }

    # Формуємо оновлені блоки підпису
    $sigLine   = "DigitalSignature: `$hash"
    $shaFooter = "`r`n`r`n---`r`n`r`n**Підпис SHA-256 (вміст сторінки):** `$hash"

    # Якщо в документі вже є блок `DigitalSignature:` — замінимо, інакше додамо внизу перед футером
    if(($content -split "`r?`n") -match '^\s*DigitalSignature:'){
      $content = (($content -split "`r?`n") | ForEach-Object {
        if($_ -match '^\s*DigitalSignature:'){ $sigLine } else { $_ }
      }) -join "`r`n"
    } else {
      $content = $content + "`r`n`r`n" + $sigLine
    }

    # Додаємо SHA-footer і зберігаємо
    $final = $content + $shaFooter + "`r`n"
    Set-Content -LiteralPath $dst -Value $final -Encoding UTF8

    # Sidecar
    $shaSide = "$hash  $($sig.Name)`r`n"
    Set-Content -LiteralPath ($dst + '.sha256.txt') -Value $shaSide -Encoding UTF8

    Ok ("Опубліковано: {0} → SHA256 {1}" -f $sig.Name, $hash)
    $processed += $dst
  }
}

# 4) git add/commit/push
if(-not $RepoRoot){
  try{
    $root = (git -C $TargetDir rev-parse --show-toplevel 2>$null)
    if($root){ $RepoRoot = $root.Trim() } else { Warn "git-репозиторій не визначено; git-крок пропущено." }
  } catch { Warn "git недоступний; git-крок пропущено." }
}

if($RepoRoot){
  Info "git add/commit у $RepoRoot"
  $relPaths = $processed | ForEach-Object {
    # перетворюємо на шлях відносно кореня репо
    $full = Resolve-Path $_
    $rel  = (Resolve-Path $RepoRoot).Path
    ($full.Path).Substring($rel.Length).TrimStart('\','/')
  }

  if($relPaths){
    git -C $RepoRoot add -- $relPaths | Out-Null
    # також sidecar-файли
    $sidecars = $processed | ForEach-Object {
      $full = Resolve-Path ($_ + '.sha256.txt')
      $rel  = (Resolve-Path $RepoRoot).Path
      ($full.Path).Substring($rel.Length).TrimStart('\','/')
    }
    git -C $RepoRoot add -- $sidecars | Out-Null

    $pending = git -C $RepoRoot status --porcelain
    if([string]::IsNullOrWhiteSpace($pending)){
Write-Warning '���� ��� ��� �����.'
    } else {
Write-Host '��������� Signal ���������.'
      git -C $RepoRoot commit -m $msg | Out-Null
      Write-Host 'git commit ��������.'
      if($GitPush){
        git -C $RepoRoot push | Out-Null
        Write-Host 'git push ��������.'
      }
    }
  } else {
Write-Warning '���� ��� ��� �����.'
  }
}

Write-Host '��������� Signal ���������.'
# >>> CHECHA LOG END >>>
try { Stop-Transcript | Out-Null } catch {}
# <<< CHECHA LOG END <<<
























