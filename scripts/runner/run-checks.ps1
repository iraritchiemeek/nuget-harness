# Done-when checks 1-3: capture every check request into -Dir, then evaluate the responses.
param([Parameter(Mandatory)] [string]$Dir)
& "$PSScriptRoot\capture.ps1" -Dir $Dir
& "$PSScriptRoot\check.ps1" -Dir $Dir
