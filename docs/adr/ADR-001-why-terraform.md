# ADR-001: Why Terraform

## Status

Accepted

## Problem

The platform needs a single, auditable way to provision AWS infrastructure
(networking, IAM, EKS, and the supporting services planned after it) that
can be code-reviewed, versioned, and reproduced identically across
environments. Console changes and ad-hoc scripts don't give us a diffable
plan before something happens to the account, and they don't compose into
reusable modules.

## Decision

Use Terraform (HCL) as the only supported way to provision infrastructure
in this repository. Every resource is defined declaratively, state is
tracked in a remote backend (see the planned `s3-remote-state` module),
and changes go through `plan` → review → `apply`.

## Trade-offs

- **State is a real artifact to manage.** Unlike CloudFormation, Terraform
  state isn't implicit. It has to be stored, locked, and protected from
  concurrent writes. This is a genuine operational burden that
  CloudFormation avoids by keeping state inside AWS itself.
- **HCL is not a general-purpose language.** Conditionals, loops, and type
  handling are more limited than a real programming language. For a
  platform foundation of this size (VPC/IAM/EKS plus a handful of planned
  services) that ceiling hasn't been hit, but it's a real constraint for
  very large, highly dynamic infrastructure graphs.
- **No automatic drift reconciliation.** Terraform tells you about drift
  on the next `plan`, but it doesn't continuously reconcile like a
  Kubernetes controller does. Anyone editing resources by hand outside
  Terraform creates drift that isn't caught until someone runs `plan`
  again.

## Alternatives Considered

- **AWS CloudFormation**: no separate state file to manage, native to
  AWS, but AWS-only (this platform is AWS-only today, but a Terraform
  skill set and module library isn't stranded if that changes). It has
  historically been slower to support new AWS features than the Terraform
  AWS provider, and its module ecosystem (nested stacks) is far less
  mature than the Terraform Registry.
- **AWS CDK**: a real programming language (TypeScript/Python), which is
  genuinely more expressive, but it synthesizes to CloudFormation
  underneath, so it inherits CloudFormation's stack size and update
  behavior limits while adding a build/synth step on top. For
  infrastructure meant to be read and reviewed by people who don't
  necessarily write application code, HCL's declarative-only shape is a
  feature, not a limitation.
- **Pulumi**: similar expressiveness benefits to CDK, multi-cloud like
  Terraform, but still requires a state backend (same operational burden
  noted above) with a smaller community/module ecosystem than Terraform's
  registry as of this writing.
- **ClickOps (manual console changes)**: fastest for a one-off
  experiment, but leaves no diff, no review step, and no reproducibility.
  Not viable for anything this repository calls production-ready.

## Production Considerations

- Remote state uses S3 (versioned, encrypted) with DynamoDB for locking,
  tracked as the planned `s3-remote-state` module rather than assumed to
  exist. Until it ships, no environment in this repository should run
  with local state.
- Provider and Terraform core versions are pinned per module
  (`required_version`, `required_providers`) so `terraform init` is
  reproducible. See [terraform-standards.md](../terraform-standards.md).
- `terraform plan` output is the artifact a reviewer actually reads on a
  pull request. CI runs `fmt`, `validate`, `tflint`, `tfsec`, and
  `checkov` on every change (see `.github/workflows/`), but a human still
  reviews the plan for anything with real blast radius (IAM, security
  groups, subnet CIDRs).
