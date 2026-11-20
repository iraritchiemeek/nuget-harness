# Done-when check 7: the gallery checkout has no changes to tracked files (source or config),
# and evidence/01/config.diff contains no hunks. Untracked files (packages pushed into
# App_Data, build output) are listed for the record but are not changes to the app.
. "$PSScriptRoot\common.ps1"
$checkDir = Join-Path $OutDir 'checks'
New-Item -ItemType Directory -Force -Path $checkDir | Out-Null
$head = (& git -C $GalleryDir rev-parse HEAD).Trim()
$diff = (& git -C $GalleryDir diff HEAD | Out-String)
$stat = (& git -C $GalleryDir status --porcelain --untracked-files=normal | Out-String)
$cfg = Get-Content (Join-Path $RepoRoot 'evidence\01\config.diff') | Where-Object { $_ -match '^(\+\+\+|---|@@)' }
@("gallery HEAD: $head", "git diff HEAD (tracked files):", $diff, "git status --porcelain:", $stat,
  "hunks in evidence/01/config.diff: $(@($cfg).Count)") | Set-Content (Join-Path $checkDir 'check7-source-diff.txt') -Encoding utf8
$ok = ($head -eq $env:GALLERY_SHA) -and [string]::IsNullOrWhiteSpace($diff) -and (@($cfg).Count -eq 0)
Write-Result 7 'config diff published, source diff empty' $ok "HEAD $($head.Substring(0,12)); tracked-file diff $(if ([string]::IsNullOrWhiteSpace($diff)) {'empty'} else {'NOT empty'}); config.diff hunks: $(@($cfg).Count) (check7-source-diff.txt)"
if (-not $ok) { throw 'source/config diff check failed' }
