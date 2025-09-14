@{
  ExcludeRules = @(
    'PSUseBOMForUnicodeEncodedFile',    # у нас UTF-8 без BOM
    'PSUseSingularNouns',               # не критично для скриптів
    'PSAvoidUsingCmdletAliases'         # вимкни, якщо свідомо юзаєш aliase (інакше прибери з цього списку)
  )
  Rules = @{
    PSUseConsistentIndentation = @{
      Enable = $true
      IndentationSize = 2
    }
  }
}
