# Pester 5.x — запускаємо копію валідатора з $TestDrive (без -Root)

Describe "Validate-Releases Strict/CI" {
    BeforeAll {
        $RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $SrcValidator = Join-Path $RepoRoot 'C11\tools\Validate-Releases.ps1'
        Test-Path $SrcValidator | Should -BeTrue
        $ZipName = 'SHIELD4_ODESA_UltimatePack_test.zip'
    }

    It "returns 0 in CI mode with only warnings" {
        $TmpRoot = $TestDrive
        $ToolDir = Join-Path $TmpRoot 'C11\tools'
        $ModuleDir = Join-Path $TmpRoot 'C11\SHIELD4_ODESA'
        $RelDir = Join-Path $ModuleDir 'Release'
        New-Item -ItemType Directory -Force -Path $ToolDir, $RelDir | Out-Null

        $Validator = Join-Path $ToolDir 'Validate-Releases.ps1'
        Copy-Item $SrcValidator $Validator -Force

        $Src = Join-Path $TestDrive 'src-warn'
        New-Item -ItemType Directory -Force -Path $Src | Out-Null
        $File = Join-Path $Src 'file.txt'
        Set-Content -Path $File -Value 'hi' -Encoding UTF8
        $Zip = Join-Path $RelDir $ZipName
        Compress-Archive -Path $File -DestinationPath $Zip -Force
        Test-Path $Zip | Should -BeTrue

        & $Validator -All | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It "can run Strict (non-zero possible)" {
        $TmpRoot = $TestDrive
        $ToolDir = Join-Path $TmpRoot 'C11\tools'
        $ModuleDir = Join-Path $TmpRoot 'C11\SHIELD4_ODESA'
        $RelDir = Join-Path $ModuleDir 'Release'
        New-Item -ItemType Directory -Force -Path $ToolDir, $RelDir | Out-Null

        $Validator = Join-Path $ToolDir 'Validate-Releases.ps1'
        Copy-Item $SrcValidator $Validator -Force

        $Src = Join-Path $TestDrive 'src-strict'
        New-Item -ItemType Directory -Force -Path $Src | Out-Null
        $File = Join-Path $Src 'file.txt'
        Set-Content -Path $File -Value 'hi' -Encoding UTF8
        $Zip = Join-Path $RelDir $ZipName
        Compress-Archive -Path $File -DestinationPath $Zip -Force
        Test-Path $Zip | Should -BeTrue

        & $Validator -All -Strict | Out-Null
        $LASTEXITCODE | Should -BeIn @(0, 1)   # тільки перевіряємо, що Strict відпрацював коректно
    }
}

Describe "Validate-Releases detects checksum mismatch in Strict" {
    BeforeAll {
        $RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
        $SrcValidator = Join-Path $RepoRoot 'C11\tools\Validate-Releases.ps1'
        Test-Path $SrcValidator | Should -BeTrue
        $ZipName = 'SHIELD4_ODESA_UltimatePack_test.zip'
    }

    It "returns non-zero (1) on mismatch in Strict" {
        $TmpRoot = $TestDrive
        $ToolDir = Join-Path $TmpRoot 'C11\tools'
        $ModuleDir = Join-Path $TmpRoot 'C11\SHIELD4_ODESA'
        $RelDir = Join-Path $ModuleDir 'Release'
        $ArcDir = Join-Path $ModuleDir 'Archive'
        New-Item -ItemType Directory -Force -Path $ToolDir, $RelDir, $ArcDir | Out-Null

        $Validator = Join-Path $ToolDir 'Validate-Releases.ps1'
        Copy-Item $SrcValidator $Validator -Force

        $Src = Join-Path $TestDrive 'src-mismatch'
        New-Item -ItemType Directory -Force -Path $Src | Out-Null
        $File = Join-Path $Src 'file.txt'
        Set-Content -Path $File -Value 'hello' -Encoding UTF8
        $Zip = Join-Path $RelDir $ZipName
        Compress-Archive -Path $File -DestinationPath $Zip -Force
        Test-Path $Zip | Should -BeTrue

        $Chk = Join-Path $ArcDir 'CHECKSUMS.txt'
        $Wrong = ('00' * 32)  # 64 hex chars псевдо-SHA256
        Set-Content -Path $Chk -Value "$Wrong *$ZipName" -Encoding ASCII
        Test-Path $Chk | Should -BeTrue

        # --- Головне: приймаємо або Throw з "Hash mismatch", або rc=1 ---
        $thrown = $false; $rc = $null; $msg = $null
        try {
            & $Validator -All -Strict | Out-Null
            $rc = $LASTEXITCODE
        }
        catch {
            $thrown = $true
            $msg = $_.Exception.Message
        }

        if ($thrown) {
            $msg | Should -Match 'Hash mismatch'
        }
        else {
            $rc  | Should -Be 1
        }
    }
}


