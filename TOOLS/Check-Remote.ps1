$origin = (git remote get-url origin 2>$null | Select-Object -Last 1)
$branch = (git rev-parse --abbrev-ref HEAD 2>$null | Select-Object -Last 1)

$up = $null
$null = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
if ($LASTEXITCODE -eq 0) {
    $up = (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Select-Object -Last 1)
}

if (-not $origin) { $origin = '(none)' }
if (-not $branch) { $branch = '(detached/none)' }
if (-not $up) { $up = '(none)' }

"origin:   $origin"
"branch:   $branch"
"upstream: $up"

