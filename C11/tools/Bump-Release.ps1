param(
    [ValidateSet("patch", "minor", "major")]$Part = "patch",
    [switch]$DryRun
)

$repo = Resolve-Path "$PSScriptRoot\..\.."

# Завжди тягнемо теги з origin
git -C $repo fetch --tags --prune | Out-Null

# Беремо лише валідні семвер-теги vX.Y.Z
$tags = git -C $repo tag --list "v*" | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }
if (-not $tags) { throw "No v* tags found on remote" }

# Знаходимо макс. версію
$last = ($tags | Sort-Object { [version]($_.TrimStart('v')) })[-1]
$cur = [version]($last.TrimStart('v'))

# Обчислюємо наступну
$next = switch ($Part) {
    "patch" { [version]::new($cur.Major, $cur.Minor, $cur.Build + 1) }
    "minor" { [version]::new($cur.Major, $cur.Minor + 1, 0) }
    "major" { [version]::new($cur.Major + 1, 0, 0) }
}
$tag = "v{0}.{1}.{2}" -f $next.Major, $next.Minor, $next.Build

if ($DryRun) { Write-Host "Would tag $tag (from $last)"; exit 0 }

git -C $repo tag -a $tag -m $tag
git -C $repo push origin $tag
Write-Host "Pushed $tag (prev was $last)"


