function Compress-Files([string[]]$files,[string]$zipPath,[switch]$Staged){
  if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
  }

  if ($Staged) {
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("dao_stage_" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
      # копіювання унікальних файлів
      $seen = @{}
      foreach ($f in $files) {
        $name = Split-Path $f -Leaf
        if ($seen.ContainsKey($name)) {
          $base = [IO.Path]::GetFileNameWithoutExtension($name)
          $ext  = [IO.Path]::GetExtension($name)
          $name = "{0}__{1}{2}" -f $base, ([Math]::Abs(($seen[$name] + $f).GetHashCode())), $ext
        }
        $seen[$name] = $f
        Copy-Item -LiteralPath $f -Destination (Join-Path $stage $name) -Force
      }

      # перевіряємо, що щось є у стаджингу
      $stageFiles = Get-ChildItem -LiteralPath $stage -File
      if (-not $stageFiles -or $stageFiles.Count -eq 0) {
        throw "Nothing staged to compress (stage is empty): $stage"
      }

      # важливо: -Path, а не -LiteralPath (бо '*')
      Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -Force
    }
    finally {
      Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  else {
    Compress-Archive -Path $files -DestinationPath $zipPath -Force
  }
}

