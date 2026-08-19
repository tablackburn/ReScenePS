@{
    IncludeRules = @('*')

    ExcludeRules = @(
        # This module reports progress to the user as it works -- extracting a
        # stored file, reconstructing a sample, validating a CRC -- and that
        # output is the point, not a debugging leftover. Write-Information would
        # be invisible without -InformationAction, and Write-Output would put
        # progress text on the success stream where it would be captured by
        # callers along with real return values.
        #
        # PowerShellBuild's own bundled analyzer settings exclude this rule for
        # the same reason. Excluded deliberately here rather than left to the
        # default, so the exclusion survives pointing the build at this file.
        'PSAvoidUsingWriteHost'
    )
}
