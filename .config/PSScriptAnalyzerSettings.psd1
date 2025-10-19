@{
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile',    # UTF-8 без BOM ок
        'PSUseSingularNouns',
        'PSAvoidUsingCmdletAliases'         # прибери з цього списку, якщо хочеш строгі імена
    )
    Rules        = @{
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 2
        }
    }
}


