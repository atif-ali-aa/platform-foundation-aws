# Terraform Standards

Conventions every module and environment in this repository follows. If a
PR deviates from these without a stated reason, expect a review comment
asking why. See [repository-standards.md](repository-standards.md#code-review-process)
for the review process itself.

## Module structure

Every module under `modules/*` has exactly these files:

```text
modules/<name>/
├── main.tf
├── variables.tf
├── outputs.tf
└── README.md
```

No `locals.tf`, no `data.tf`, and no splitting `main.tf` into a dozen
files for a module this size. See [ADR-001](adr/ADR-001-why-terraform.md)
for why this repository favors HCL's declarative simplicity over clever
structure. If a module genuinely outgrows a single `main.tf` (the `eks`
module is the most likely candidate), splitting by resource group
(`main.tf`, `node-groups.tf`, `irsa.tf`) is acceptable. Splitting for its
own sake is not.

## Naming conventions

- **Resources**: `snake_case`, named after what they are, not what
  they're for. Use `aws_subnet.private`, not `aws_subnet.for_eks_nodes`.
  The "for what" belongs in a tag or a comment, not baked into a name
  that has to change if the consumer changes.
- **Variables**: `snake_case`, and named the same as the concept they
  configure. Use `vpc_cidr`, not `cidr` (ambiguous once a module has
  three CIDR-shaped inputs) and not `vpc_cidr_block_input` (redundant).
- **Deployed resource names** (the actual AWS-side `Name` tag or resource
  name, as opposed to the Terraform resource address) follow
  `<environment>-<module>-<purpose>`, e.g. `prod-vpc-private-a`,
  `staging-eks-node-group-default`. This is what shows up in the AWS
  console and in CloudTrail, so it needs to be identifiable without
  opening Terraform.

## Variable validation

Every variable that has a constrained set of valid values gets a
`validation` block, not a comment saying what's valid, an actual
enforced check. Examples used throughout the production modules:

```hcl
variable "environment" {
  description = "Deployment environment name, used in resource naming and tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
```

CIDR inputs are validated with `can(cidrhost(var.x, 0))`, counts and
sizes get range checks, and enum-like strings (NAT strategy, log
retention tier) get `contains()` checks. A variable without validation is
a variable whose invalid values are discovered at `apply` time inside AWS
instead of at `plan` time in review. See [security.md](security.md) for
why that distinction matters for anything touching IAM or networking.

## Descriptions

Every variable and output has a `description`. "What this is" belongs in
`description`. "Why the default is what it is" belongs in the module
README's design-decisions section. `tflint`'s
`terraform_documented_variables` and `terraform_documented_outputs` rules
enforce the former in CI, but the latter has to be written by hand
because there's no automated check for "did you explain your reasoning."

## Provider and version pinning

Every module declares:

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
```

Pinned with `~>` (allow patch/minor within a major), not left unpinned.
An unpinned provider version means `terraform init` on two different
days can silently resolve to two different provider versions with
different behavior.

## Formatting and linting

`terraform fmt -recursive`, `tflint` (config in `.tflint.hcl`, AWS
ruleset enabled), `tfsec`, and `checkov` all run in CI on every PR. See
`.github/workflows/terraform-ci.yml`. None of these are optional local
suggestions; a PR that fails any of them doesn't merge. Run them locally
before opening a PR (or install the pre-commit hooks in
`.pre-commit-config.yaml`) to avoid a slow review round trip.

## Module development standards

- A module change updates its `README.md` in the same PR: inputs,
  outputs, and any example that referenced the changed behavior. A stale
  module README is treated as a bug, not a follow-up.
- Breaking changes (removing a variable, changing a default that affects
  existing infrastructure, renaming a resource in a way that forces
  replacement) are called out explicitly in the PR description and in
  `CHANGELOG.md`. See
  [repository-standards.md](repository-standards.md#versioning-strategy).
- A module doesn't reach into another module's resources directly; it
  takes inputs and returns outputs. If `eks` needs something from `vpc`,
  it's passed as a variable from the environment composing both, not
  read via a `data` source reaching across module boundaries.
