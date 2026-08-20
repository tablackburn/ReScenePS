@{
    IncludeRules = @('*')

    # Scope analysis to actionable severities. Microsoft's documented settings
    # example does the same; without it Information-level findings are in scope
    # with nothing having decided that they should be.
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # This module reports progress to the user as it works -- extracting a
        # stored file, reconstructing a sample, validating a CRC -- and that
        # output is the point, not a debugging leftover. Write-Information would
        # be invisible without -InformationAction, and Write-Output would put
        # progress text on the success stream where callers would capture it
        # alongside real return values.
        #
        # Excluded repository-wide rather than suppressed per function. The
        # targeted SuppressMessageAttribute form Microsoft documents was tried
        # first and does not fit here: the printing happens inside nested
        # functions and script blocks within the entry-point commands, which a
        # function-scoped attribute does not reach -- 65 of 127 findings
        # survived it. Microsoft's own settings example excludes this same rule.
        'PSAvoidUsingWriteHost'
    )
}
