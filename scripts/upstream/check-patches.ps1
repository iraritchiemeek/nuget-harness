# Spec 03 check 1 and the patch half of check 6, on a NuGetGallery checkout in gallery/:
#   - each patch applies on its own, and touches exactly the files listed for it in upstream/fixes.json
#   - each wrong fix applies on top of its patch's tests, and touches no tests
#   - the three patches apply in all six orders, and every order gives the same tree
. "$PSScriptRoot/../runner/common.ps1"
$upstream = Join-Path $RepoRoot 'upstream'
$fixes = Get-Content (Join-Path $upstream 'fixes.json') -Raw | ConvertFrom-Json

function Invoke-Git { & git -C $GalleryDir @args; if ($LASTEXITCODE -ne 0) { throw "git $args exited $LASTEXITCODE" } }
function Get-Tree([scriptblock]$Apply) {
    Invoke-Git reset --quiet --hard | Out-Null
    & $Apply
    Invoke-Git add --all | Out-Null
    return (Invoke-Git write-tree)
}

foreach ($pr in 'a', 'b', 'c') {
    $fix = $fixes.$pr
    $patch = Join-Path $upstream $fix.patch
    $tree = Get-Tree { Invoke-Git apply --whitespace=error $patch }
    $touched = @(Invoke-Git diff --cached --name-only HEAD)
    if (Compare-Object $touched $fix.files) { throw "$($fix.patch) touches $($touched -join ', '); upstream/fixes.json lists $($fix.files -join ', ')" }
    [void](Get-Tree { Invoke-Git apply '--include=tests/*' $patch; Invoke-Git apply (Join-Path $upstream "wrong-fixes/$($fix.patch)") })
    $wrong = @(Invoke-Git apply --numstat (Join-Path $upstream "wrong-fixes/$($fix.patch)"))
    if (@($wrong | Where-Object { $_ -match '\ttests/' }).Count) { throw "wrong-fixes/$($fix.patch) touches tests" }
    $size = @(Invoke-Git apply --numstat $patch | ForEach-Object { $_ -replace '\s+', ' ' })
    Write-Summary "- check 1, $($fix.patch): applies on its own (tree $tree); added and deleted lines per file: $($size -join '; ')"
}

$trees = foreach ($order in 'abc', 'acb', 'bac', 'bca', 'cab', 'cba') {
    Get-Tree { foreach ($pr in $order.ToCharArray()) { Invoke-Git apply (Join-Path $upstream $fixes."$pr".patch) } }
}
$distinct = @($trees | Sort-Object -Unique)
if ($distinct.Count -ne 1) { throw "the patches give different trees in different orders: $($distinct -join ', ')" }
Invoke-Git reset --quiet --hard | Out-Null
Write-Summary "- check 6, patches: all six orders apply and give the same tree ($distinct)"
