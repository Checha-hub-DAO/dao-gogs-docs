@{
  ExcludeRules = @(
    'PSUseBOMForUnicodeEncodedFile',   # не валимо за BOM
    'PSUseConsistentIndentation',      # тимчасово вимкнено; поправимо поступово
    'PSAvoidUsingWriteHost'            # якщо зустрічається у твоїх тулінгах
  )
  Rules = @{
    PSUseConsistentIndentation = @{
      Enable = $true
      IndentationSize = 2
    }
  }
}
