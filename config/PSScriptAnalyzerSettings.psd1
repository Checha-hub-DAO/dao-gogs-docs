@{
    Severity = @('Error', 'Warning')
    Rules    = @{
        # --- Style & Safety ---
        PSUseConsistentWhitespace                    = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckPipe       = $true
            CheckSeparator  = $true
        }
        PSUseConsistentIndentation                   = @{
            Enable          = $true
            Kind            = 'space'
            IndentationSize = 4
        }
        PSAlignAssignmentStatement                   = @{ Enable = $true }
        PSUseBOMForUnicodeEncodedFile                = @{ Enable = $false } # prefer UTF-8 without BOM
        PSPlaceOpenBrace                             = @{
            Enable       = $true
            OnSameLine   = $true
            NewLineAfter = $true
        }
        PSPlaceCloseBrace                            = @{
            Enable       = $true
            NewLineAfter = $true
        }
        PSUseShouldProcessForStateChangingFunctions  = @{ Enable = $true }
        PSAvoidUsingWriteHost                        = @{
            Enable   = $true
            Severity = 'Warning' # allow but warn
        }
        PSAvoidGlobalVars                            = @{ Enable = $true }
        PSAvoidUsingEmptyCatchBlock                  = @{ Enable = $true }
        PSAvoidTrailingWhitespace                    = @{ Enable = $true }
        PSPossibleIncorrectUsageOfAssignmentOperator = @{ Enable = $true }
        PSUseApprovedVerbs                           = @{ Enable = $true }

        # --- Practical deviations for CheCha ---
        PSAvoidUsingInvokeExpression                 = @{
            Enable   = $true
            Severity = 'Error'
        }
        PSReviewUnusedParameter                      = @{ Enable = $false } # CheCha scaffolds often reserve parameters
        PSMisleadingBacktick                         = @{ Enable = $true }
        PSUseDeclaredVarsMoreThanAssignments         = @{ Enable = $true }

        # --- Formatting ---
        PSUseConsistentFormatting                    = @{ Enable = $true }
    }

    # CustomIncludeRules or ExcludeRules can be added per-repo if needed
}


