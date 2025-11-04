[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$Config = "D:\CHECHA_CORE\ITETA\config.yaml"
)

# читаємо оригінал
$raw = Get-Content -LiteralPath "D:\CHECHA_CORE\TOOLS\Publish-ITETA_Signal.ps1" -Raw

# вирізаємо перший param(...) (все до нього і сам param — відкидаємо)
$pm = [regex]::Match($raw, 'param\s*\(', 'IgnoreCase')
if ($pm.Success) {
  $start = $pm.Index + $pm.Length
  $i = $start; $d = 1
  while ($i -lt $raw.Length -and $d -gt 0) { if($raw[$i]-eq '('){$d++} elseif($raw[$i]-eq ')'){$d--}; $i++ }
  $body = $raw.Substring($i)
} else {
  $body = $raw
}

# безпечна заміна "ITETA Signal entries …"
$body = [regex]::Replace(
  $body,
  '(?im)^.*ITETA\s+Signal\s+entries.*$',
  'Write-Host "ITETA Signal entries ($((Get-Date).ToString(''yyyy-MM-dd''))) + SHA256"'
)

# виконати тіло (WhatIf працює як common parameter завдяки CmdletBinding)
$ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create($body)), $null)
