# Spec 03, PR C's extra check: the manage packages page on the running app, before and after the fix,
# for the account that received the ownership requests and the account that sent them.
#   1. one normal request: the page works for both accounts (the control)
#   2. a second request, for a registration with no versions, set up in this run's database: before
#      the fix the page fails for both accounts
#   3. after the fix the page works for both, the normal request is exactly as in the control, and the
#      request with no versions is listed
#   4. what the listed request links to: the package page, the manage page, reject and confirm
. "$PSScriptRoot/../runner/common.ps1"
. "$PSScriptRoot/session.ps1"
$normalId = 'Serilog'; $emptyId = 'Harness.NoVersions'
$page = '/account/Packages'
$bad = New-Object 'Collections.Generic.List[string]'
$table = New-Object 'Collections.Generic.List[string]'
$table.Add('| Step | Account | Expected | Observed | Result |'); $table.Add('|---|---|---|---|---|')
function Add-Row([string]$Step, [string]$User, [string]$Expected, [string]$Observed) {
    $ok = $Observed -clike $Expected
    if (-not $ok) { $bad.Add("$Step, ${User}: $Observed") }
    $table.Add("| $Step | $User | $Expected | $Observed | $(if ($ok) { 'as expected' } else { 'NOT as expected' }) |")
}
function Add-Request([string]$Id) {
    $rows = Invoke-Sql -Database 'NuGetGallery' -Query @"
INSERT INTO [dbo].[PackageOwnerRequests] ([PackageRegistrationKey], [NewOwnerKey], [RequestingOwnerKey], [ConfirmationCode], [RequestDate])
SELECT r.[Key], n.[Key], o.[Key], LOWER(REPLACE(CONVERT(nvarchar(36), NEWID()), '-', '')), GETUTCDATE()
FROM [dbo].[PackageRegistrations] r, [dbo].[Users] n, [dbo].[Users] o
WHERE r.[Id] = N'$Id' AND n.[Username] = N'receiver' AND o.[Username] = N'sender';
SELECT COUNT(*) AS n FROM [dbo].[PackageOwnerRequests] q JOIN [dbo].[PackageRegistrations] r ON r.[Key] = q.[PackageRegistrationKey] WHERE r.[Id] = N'$Id';
"@
    if ($rows[0].n -ne 1) { throw "$($rows[0].n) requests for $Id, expected 1" }
}
# The page as an account sees it: the status, and the requests in the data the page is built from.
function Get-ManagePage([string]$User) {
    $r = Invoke-Session $User $page
    $o = [pscustomobject]@{ Status = $r.Status; Body = $r.Body; Received = @(); Sent = @() }
    if ($r.Status -eq 200) {
        $m = [regex]::Match($r.Body, '(?s)var initialData = (\{.*?\});\s*</script>')
        if (-not $m.Success) { throw 'the page has no initialData' }
        $data = ConvertFrom-Json $m.Groups[1].Value
        $o.Received = @($data.RequestsReceived); $o.Sent = @($data.RequestsSent)
    }
    return $o
}
function Get-Listed($Requests) { return (@($Requests | ForEach-Object { "$($_.Id) (accept $($_.CanAccept), manage $($_.CanCancel))" }) -join ', ') }
function Get-Json($Requests, [string]$Id) { return (@($Requests | Where-Object { $_.Id -ceq $Id }) | ConvertTo-Json -Depth 8 -Compress) }

Register-TestAccount 'receiver'
Register-TestAccount 'sender'
$code = Publish-Package -File (Get-SeedPackage -Id $normalId -Version '4.2.0' -CacheDir $env:RUNNER_TEMP) -ApiKey (Get-Content $ApiKeyFile -Raw)
if ($code -ne 201) { throw "push of $normalId returned $code" }
foreach ($u in 'receiver', 'sender') { Connect-Account $u }

# ---- 1. control ---------------------------------------------------------------------------------
Add-Request $normalId
$normalRow = "$normalId (accept {0}, manage {1})"
$receivedPage = Get-ManagePage 'receiver'; $sentPage = Get-ManagePage 'sender'
Add-Row '1. unpatched, normal request only' 'receiver' "200 $($normalRow -f 'True', 'False')" "$($receivedPage.Status) $(Get-Listed $receivedPage.Received)"
Add-Row '1. unpatched, normal request only' 'sender' "200 $($normalRow -f 'False', 'True')" "$($sentPage.Status) $(Get-Listed $sentPage.Sent)"
$controlReceived = Get-Json $receivedPage.Received $normalId; $controlSent = Get-Json $sentPage.Sent $normalId

# ---- 2. the bug -----------------------------------------------------------------------------------
[void](Invoke-Sql -Database 'NuGetGallery' -Query @"
DECLARE @columns nvarchar(max), @values nvarchar(max), @sql nvarchar(max);
SELECT @columns = STRING_AGG(QUOTENAME(c.name), ', '), @values = STRING_AGG(CASE WHEN c.name = 'Id' THEN N'N''$emptyId''' ELSE N'0' END, N', ')
FROM sys.columns c WHERE c.object_id = OBJECT_ID('dbo.PackageRegistrations') AND c.is_identity = 0 AND c.is_computed = 0 AND c.system_type_id <> 189 AND (c.is_nullable = 0 OR c.name = 'Id');
SET @sql = N'INSERT INTO [dbo].[PackageRegistrations] (' + @columns + N') VALUES (' + @values + N')';
EXEC (@sql);
INSERT INTO [dbo].[PackageRegistrationOwners] ([PackageRegistrationKey], [UserKey])
SELECT r.[Key], u.[Key] FROM [dbo].[PackageRegistrations] r, [dbo].[Users] u WHERE r.[Id] = N'$emptyId' AND u.[Username] = N'sender';
"@)
$versions = (Invoke-Sql -Database 'NuGetGallery' -Query "SELECT COUNT(*) AS n FROM [dbo].[Packages] p JOIN [dbo].[PackageRegistrations] r ON r.[Key] = p.[PackageRegistrationKey] WHERE r.[Id] = N'$emptyId'")[0].n
if ($versions -ne 0) { throw "$emptyId has $versions versions" }
Add-Request $emptyId
foreach ($u in 'receiver', 'sender') {
    $r = Get-ManagePage $u
    Add-Row '2. unpatched, with the request for an ID with no versions' $u '500 ArgumentNullException*package*PackageViewModelFactory*' "$($r.Status) $(if ($r.Status -ne 200) { Get-ExceptionText $r.Body })"
}
if ($bad.Count) {
    Write-Summary (@('') + $table.ToArray() + @('') -join "`n")
    throw "the bug did not reproduce as described: $($bad -join '; ')"
}

# ---- 3. the fix -----------------------------------------------------------------------------------
& "$PSScriptRoot/rebuild-patched.ps1" -Patch (Join-Path $RepoRoot 'upstream/c-owner-requests.patch')
foreach ($u in 'receiver', 'sender') { Connect-Account $u }
$receivedPage = Get-ManagePage 'receiver'; $sentPage = Get-ManagePage 'sender'
Add-Row '3. patched' 'receiver' "200 $($normalRow -f 'True', 'False'), $emptyId (accept True, manage False)" "$($receivedPage.Status) $(Get-Listed ($receivedPage.Received | Sort-Object Id -Descending))"
Add-Row '3. patched' 'sender' "200 $($normalRow -f 'False', 'True'), $emptyId (accept False, manage False)" "$($sentPage.Status) $(Get-Listed ($sentPage.Sent | Sort-Object Id -Descending))"
Add-Row '3. the normal request, against step 1' 'receiver' 'identical' $(if ((Get-Json $receivedPage.Received $normalId) -ceq $controlReceived) { 'identical' } else { 'different' })
Add-Row '3. the normal request, against step 1' 'sender' 'identical' $(if ((Get-Json $sentPage.Sent $normalId) -ceq $controlSent) { 'identical' } else { 'different' })

# ---- 4. the links of the listed request -----------------------------------------------------------
if (-not $bad.Count) {
    $request = @($receivedPage.Received | Where-Object { $_.Id -ceq $emptyId })[0]
    Add-Row '4. package page' 'sender' '404' "$((Invoke-Session 'sender' $request.PackageUrl).Status)"
    Add-Row '4. manage page (no link to it is shown)' 'sender' '404' "$((Invoke-Session 'sender' "/packages/$emptyId/Manage").Status)"
    $r = Invoke-Session 'receiver' $request.RejectUrl @{ '__RequestVerificationToken' = Get-AntiforgeryToken $receivedPage.Body }
    Add-Row '4. reject' 'receiver' '200' "$($r.Status)"
    $receivedPage = Get-ManagePage 'receiver'
    Add-Row '4. after the reject' 'receiver' "200 $($normalRow -f 'True', 'False')" "$($receivedPage.Status) $(Get-Listed $receivedPage.Received)"
    Add-Request $emptyId
    $receivedPage = Get-ManagePage 'receiver'
    $request = @($receivedPage.Received | Where-Object { $_.Id -ceq $emptyId })[0]
    $r = Invoke-Session 'receiver' $request.ConfirmUrl @{ '__RequestVerificationToken' = Get-AntiforgeryToken $receivedPage.Body }
    Add-Row '4. confirm, on a new request' 'receiver' '200' "$($r.Status)"
    $owners = (Invoke-Sql -Database 'NuGetGallery' -Query "SELECT COUNT(*) AS n FROM [dbo].[PackageRegistrationOwners] o JOIN [dbo].[PackageRegistrations] r ON r.[Key] = o.[PackageRegistrationKey] WHERE r.[Id] = N'$emptyId'")[0].n
    Add-Row '4. owners of the ID after the confirm' 'database' '2' "$owners"
}
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'checks') | Out-Null
Write-Utf8File (Join-Path $OutDir 'checks/spec03-c-pages.md') $table
Write-Summary (@('') + $table.ToArray() + @('') -join "`n")
if ($bad.Count) { throw "not as the spec expects: $($bad -join '; ')" }
