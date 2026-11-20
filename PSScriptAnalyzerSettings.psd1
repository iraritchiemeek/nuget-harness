# PSScriptAnalyzer settings for the harness scripts. The lint workflow runs every rule at
# Error and Warning severity; a rule is excluded only with the reason next to it.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The scripts run as GitHub Actions steps, where the host stream is the run log that
        # serves as evidence. Write-Output would mix log lines into function return values.
        'PSAvoidUsingWriteHost'
    )
}
