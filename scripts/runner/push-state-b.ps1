# Spec 02 amendment A2: turn state A into state B by pushing seed/state-b.txt through the old app's
# V2 push endpoint. Every push must answer 201.
#
# The restored snapshot holds no usable credential: the seed account's password and API key lived
# only in the seeding run's RUNNER_TEMP. So a second account is made through the site's forms
# (new-account.ps1). The gallery accepts a new version only from an owner of the ID, and an
# ownership request needs the current owner to accept it by signing in (exploratory record run
# 44665262875: the first push, made before the grant, was answered 403). The one step that does not
# go through the app is therefore a SQL row: the new account is made a co-owner of the IDs it pushes
# that already exist (PackageRegistrationOwners). It touches no package row, and every package row
# comes from a push. An ID that does not exist yet (amendment A9: a new ID changes package-ids
# answers) needs no grant: its first push creates it, owned by the pushing account. A missed grant
# still fails, because the push is then answered 403, not 201.
param([string]$List = (Join-Path $PSScriptRoot '..\..\seed\state-b.txt'))
. "$PSScriptRoot\common.ps1"
$entries = @(Get-Content $List | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object {
    $p = $_ -split '\s+'
    [pscustomobject]@{ Id = $p[0]; Version = $p[1] }
})

& "$PSScriptRoot\new-account.ps1" -Username 'stateb' -Email 'stateb@example.com'
$apiKey = Get-Content $ApiKeyFile -Raw

$ids = (@($entries | ForEach-Object { "N'$($_.Id)'" } | Sort-Object -Unique)) -join ', '
$granted = @(Invoke-Sql -Database 'NuGetGallery' -Query @"
INSERT INTO [dbo].[PackageRegistrationOwners] ([PackageRegistrationKey], [UserKey])
SELECT r.[Key], u.[Key] FROM [dbo].[PackageRegistrations] r CROSS JOIN [dbo].[Users] u
WHERE u.[Username] = N'stateb' AND r.[Id] IN ($ids);
SELECT r.[Id] FROM [dbo].[PackageRegistrations] r
JOIN [dbo].[PackageRegistrationOwners] o ON o.[PackageRegistrationKey] = r.[Key]
JOIN [dbo].[Users] u ON u.[Key] = o.[UserKey]
WHERE u.[Username] = N'stateb';
"@ | ForEach-Object { $_.Id })
$newIds = @($entries.Id | Sort-Object -Unique | Where-Object { $granted -notcontains $_ })

$results = @("id`tversion`tstatus")
foreach ($e in $entries) {
    $file = Get-SeedPackage -Id $e.Id -Version $e.Version -CacheDir $env:RUNNER_TEMP
    $code = Publish-Package -File $file -ApiKey $apiKey
    $results += "$($e.Id)`t$($e.Version)`t$code"
    if ($code -ne 201) { throw "push of $($e.Id) $($e.Version) returned $code" }
}
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'state-b') | Out-Null
Write-Utf8File (Join-Path $OutDir 'state-b\push-results.tsv') $results
Write-Summary "- state B: pushed $($entries.Count) versions from seed/state-b.txt as account stateb (co-owner by SQL row of $($granted.Count) IDs; new IDs created by their push: $($newIds -join ', '))"
