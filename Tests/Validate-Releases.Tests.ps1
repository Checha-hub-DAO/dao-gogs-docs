BeforeAll {
  $global:RepoRoot = Resolve-Path "$PSScriptRoot\.."
  $env:GITHUB_ACTIONS = $null  # локально
}

Describe "Validate-Releases Strict/CI" {
  It "returns 0 in CI mode with only warnings" {
    $env:GITHUB_ACTIONS = "true"
    pwsh -NoProfile -File "$RepoRoot\C11\tools\Validate-Releases.ps1" -All | Out-Null
    $LASTEXITCODE | Should -Be 0
    $env:GITHUB_ACTIONS = $null
  }

  It "can run Strict (non-zero possible)" {
    pwsh -NoProfile -File "$RepoRoot\C11\tools\Validate-Releases.ps1" -All -Strict | Out-Null
    # Просто перевіримо, що процес завершився (код може бути 0 або 1 залежно від стану артефактів)
    $LASTEXITCODE | Should -BeIn @(0,1)
  }
}
