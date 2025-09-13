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
Describe "Validate-Releases detects checksum mismatch in Strict" {
  $RepoRoot = Resolve-Path "$PSScriptRoot\.."
  $TestMod  = "TESTMOD"
  $ModDir   = Join-Path $RepoRoot "C11\$TestMod"
  $RelDir   = Join-Path $ModDir "Release"
  $ArcDir   = Join-Path $ModDir "Archive"
  $Chk      = Join-Path $ArcDir "CHECKSUMS.txt"

  BeforeEach {
    Remove-Item $ModDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $RelDir,$ArcDir | Out-Null

    $tmp = Join-Path $env:TEMP ("dummy_{0}.txt" -f ([guid]::NewGuid()))
    "dummy" | Set-Content -Encoding UTF8 $tmp
    $zip = Join-Path $RelDir "${TestMod}_dummy.zip"
    Compress-Archive -Path $tmp -DestinationPath $zip -Force

    # навмисно неправильний хеш (64 нулів)
    "0" * 64 + " *$([IO.Path]::GetFileName($zip))" | Set-Content -Encoding ASCII $Chk
  }

  AfterEach {
    Remove-Item $ModDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  It "returns non-zero (1) on mismatch in Strict" {
    pwsh -NoProfile -File "$RepoRoot\C11\tools\Validate-Releases.ps1" -Module $TestMod -Strict | Out-Null
    $LASTEXITCODE | Should -Be 1
  }
}
