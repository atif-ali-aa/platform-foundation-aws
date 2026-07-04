# Repository Standards

The conventions that apply across the whole repository. Module-specific
detail lives in [terraform-standards.md](terraform-standards.md); this
document covers branching, versioning, tagging, and process.

## Branching strategy

- `main` is the only long-lived branch. There is no `develop` and no
  per-environment long-lived branches. Environment differences live in
  `environments/*` directories and `.tfvars`, not in git branches.
- Short-lived branches: `feat/<description>`, `fix/<description>`,
  `docs/<description>`, `chore/<description>`. Rebase onto `main` before
  opening a PR.

## Versioning strategy

This repository doesn't cut a single version for "the whole repo." It
versions **modules independently** via git tags, since a consumer might
want `vpc` v1.4.0 with `eks` v2.0.0 rather than being forced to upgrade
both together:

```text
modules/vpc/v1.2.0
modules/iam/v1.0.1
modules/eks/v1.3.0
```

Semantic versioning applies per module:

- **Major**: a change that forces resource replacement or removes or
  renames a variable without a compatible default.
- **Minor**: a new variable with a backward-compatible default, a new
  output, a new optional capability.
- **Patch**: a bug fix that doesn't change the module's interface.

A module still marked **Planned** doesn't get a version tag yet. It has
no implementation to version.

## Tagging strategy (AWS resources)

Distinct from git tags above, this is the AWS resource tag convention
every module applies:

| Tag | Example | Purpose |
| --- | --- | --- |
| `Environment` | `prod` | Cost allocation, environment-scoped IAM conditions |
| `ManagedBy` | `terraform` | Signals "don't hand-edit this in the console" |
| `Module` | `vpc` | Which module in this repository created the resource |
| `Repository` | `platform-foundation-aws` | Traceable back to source |

Callers can merge additional tags in via a `tags` variable on every
module. The four above are always applied regardless of what the caller
supplies, so cost allocation and provenance never depend on a caller
remembering to set them.

## State management / remote backend strategy

Each `environments/*` stack has its own state file in a shared S3 bucket
(versioned, encrypted, DynamoDB-locked). See the Planned
`s3-remote-state` module and [security.md](security.md#terraform-state-security).
State keys follow `<environment>/terraform.tfstate` so there is exactly
one state file per environment and no ambiguity about which state a
given `terraform plan` is reading.

## Security standards

See [security.md](security.md) for least privilege IAM, IRSA over static
credentials, network isolation for database subnets, and CI-enforced
`tfsec`/`checkov` scanning on every PR.

## Module development standards

See [terraform-standards.md](terraform-standards.md#module-development-standards)
for the module contract (structure, validation, documentation-stays-in-sync
requirement) every module in this repository follows.

## Code review process

- Every PR requires review from a CODEOWNER (see `CODEOWNERS`) for the
  paths it touches.
- CI must be green: `terraform fmt`, `terraform validate`, `tflint`,
  `tfsec`, `checkov`, `markdownlint` (see `.github/workflows/`), before a
  human review is meaningful. There's no point reviewing a plan built
  from unformatted, unvalidated HCL.
- A reviewer reads the **plan output**, not just the diff, for anything
  touching IAM, security groups, or subnet CIDRs. See
  [deployment-flow.md](../architecture/deployment-flow.md) for why
  `apply` stays a deliberate manual step rather than automatic on merge.
- Squash-merge is preferred so `main` history stays one commit per
  logical change.
