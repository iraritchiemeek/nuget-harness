# Put the NuGetGallery checkout into one state for upstream-fix.yml:
#   base        unchanged
#   tests-only  only the test files of the patch
#   wrong-fix   the test files of the patch, and upstream/wrong-fixes/<patch>
#   fix         the whole patch
# -Pr all means all three patches (base and fix only).
param([Parameter(Mandatory)] [ValidateSet('a', 'b', 'c', 'all')] [string]$Pr,
      [Parameter(Mandatory)] [ValidateSet('base', 'tests-only', 'wrong-fix', 'fix')] [string]$Variant)
. "$PSScriptRoot/../runner/common.ps1"
$upstream = Join-Path $RepoRoot 'upstream'
$fixes = Get-Content (Join-Path $upstream 'fixes.json') -Raw | ConvertFrom-Json
$names = if ($Pr -eq 'all') { 'a', 'b', 'c' } else { @($Pr) }
if ($Pr -eq 'all' -and $Variant -notin 'base', 'fix') { throw "variant $Variant needs one PR" }
function Invoke-Apply { & git -C $GalleryDir apply @args; if ($LASTEXITCODE -ne 0) { throw "git apply $args exited $LASTEXITCODE" } }

& git -C $GalleryDir diff --quiet HEAD
if ($LASTEXITCODE -ne 0) { throw 'the checkout already has changes' }
if ($Variant -ne 'base') {
    foreach ($n in $names) {
        $patch = Join-Path $upstream $fixes.$n.patch
        if ($Variant -eq 'fix') { Invoke-Apply $patch } else { Invoke-Apply '--include=tests/*' $patch }
        if ($Variant -eq 'wrong-fix') { Invoke-Apply (Join-Path $upstream "wrong-fixes/$($fixes.$n.patch)") }
    }
}
$changed = @(& git -C $GalleryDir diff --name-only HEAD)
Write-Summary "- variant $Variant of PR ${Pr}: changed files: $(if ($changed.Count) { $changed -join ', ' } else { 'none' })"
