# Spec 01 run log

All commands run from the operator Mac with `--profile nuget-harness`, region ap-southeast-2.
Times are UTC. Raw script output is in `evidence/01/logs/`.

## 2026-11-19 (UTC): session 1

### Step 0: orientation (read-only)
- `aws sts get-caller-identity --profile nuget-harness`: user `nuget-harness-agent`, account <account-id>.
- Base AMI: `aws ssm get-parameter --name /aws/service/ami-windows-latest/Windows_Server-2025-English-Full-Base` gave `ami-0dcf85379b0471a5d`.
- Default VPC `vpc-09d90e9d8b1de0160`. No instances existed before this run.
- I shallow-fetched NuGetGallery at `63e6ee4202b441e1c904d6f78fc7b070f36bc24f` into a scratch folder on the Mac to read it. Nothing was copied into this project. Findings that affect the plan:
  - The Validation DB context is registered only when `Gallery.AsynchronousPackageValidationEnabled` is true. Web.config sets it to `false`, so the Validation database should not be needed to boot. This still has to be confirmed on a running app.
  - `AsynchronousPackageValidationEnabled=false` should make pushed packages `Available` at once. This also still has to be confirmed (done-when 3).
  - `/api/v2/package-ids` (SQL fallback) returns at most 30 IDs. It excludes prerelease and SemVer2 versions by default and counts only `Available` and `Listed` packages.
  - `/api/v2/package-versions/{id}` returns `Package.Version`, which is the original version string from the nuspec, not the normalized one.
  - `Gallery.RejectSignedPackagesWithNoRegisteredCertificate=false`, so packages that nuget.org has repository-signed should be accepted.
  - `global.json` requires .NET SDK 8.0.318 with `rollForward: latestMajor`.

### Step 1: SSH key. Result: done
- `ssh-keygen -t ed25519 -N "" -C nuget-harness -f ~/.ssh/nuget-harness`
- `scripts/provision.sh` imported it as EC2 key pair `nuget-harness` (`key-055df88ca1ce04013`).

### Step 2: security group. Result: done
- `scripts/provision.sh` created `sg-08d3d07984aa44233` in the default VPC.
- It revokes all inbound rules, then adds exactly one: tcp/22 from <my-ip>/32 (from checkip.amazonaws.com). Tagged Project=nuget-harness.

### Step 3: launch. Result: failed twice, then blocked
- **Attempt 1.** Log: `logs/provision-1.log`. Error: `An error occurred (Unsupported) when calling the RunInstances operation: ED25519 key pairs are not supported with Windows AMIs.`
  - Fix: the instance now launches without `--key-name`. `provision.sh` substitutes the ed25519 public key into the user-data (`.state/userdata.rendered.ps1`), and the user-data writes that key to `administrators_authorized_keys` instead of fetching it from IMDS.
  - IMDSv2 is still required at launch (`HttpTokens=required`).
  - This deviates from the brief, which asked for the key to come from IMDS. The deviation is forced: IMDS only serves keys attached through `--key-name`.
- **Attempt 2.** Log: `logs/provision-2.log`. Error: `An error occurred (Blocked) when calling the RunInstances operation: This account is currently blocked and not recognized as a valid account. Please contact https://support.console.aws.amazon.com/support/home?region=us-east-1#/case/create?issueType=customer-service&serviceCode=account-management&categoryCode=account-verification if you have questions.`
- **Same call with `--dry-run`.** Result: `DryRunOperation: Request would have succeeded`. So IAM allows the launch, and the block is at account level, not from the IAM policy or the budget freeze.
- **Attempt 3** (one retry, about 25 s later). Log: `logs/provision-3.log`. Same `Blocked` error.

### Status: blocked, needs a human
EC2 `RunInstances` is refused for the whole account with error code `Blocked` (account verification). Only the account owner can clear this, through AWS Support or account verification. No agent-side workaround exists. Work stops here, as the brief requires.

- **Resources created (both free):** key pair `nuget-harness`, security group `sg-08d3d07984aa44233`.
- **Not created:** no instance and no volume.
- **To resume:** once the account is unblocked, re-run `scripts/provision.sh`. It is idempotent: it re-uses the key pair and security group, and re-points the ingress rule at the current IP.
