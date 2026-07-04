# Security Policy

## Supported Versions

This repository is a reference platform foundation, not a versioned
software release. Security guidance applies to the `main` branch, which
represents the current production-ready state of the `vpc`, `iam`, and
`eks` modules. Modules marked **Planned** in the README have no security
posture to evaluate yet: there is no implementation.

## Reporting a Vulnerability

If you find a security issue in the production modules (`modules/vpc`,
`modules/iam`, `modules/eks`), for example an overly permissive IAM
policy, a security group rule that shouldn't be open by default, or a
Terraform pattern that would expose state or secrets, please do not open
a public issue.

Instead, report it privately via GitHub's
["Report a vulnerability"](../../security/advisories/new) flow under the
Security tab of this repository. This creates a private advisory visible
only to maintainers until a fix is available.

Please include:

- The module and file affected
- The specific misconfiguration and why it's a risk (blast radius, not just
  "this is bad practice")
- A suggested fix or mitigation, if you have one

## What counts as a security issue here

Since this repository ships Terraform modules rather than a running
service, "vulnerability" mostly means **insecure defaults** that a
consumer of the module would inherit without realizing it:

- IAM policies broader than the documented least-privilege intent
- Security groups / NACLs open beyond what the module README claims
- Missing encryption defaults (e.g. unencrypted EBS/EKS secrets at rest)
- Terraform state handling that could leak secrets (e.g. secrets in plain
  variables instead of `sensitive = true`, or committed `.tfvars`)

General Terraform style issues or missing features in **Planned** modules
are not security reports. Please use a regular issue for those.

## Automated Scanning

This repository runs `tfsec` and `checkov` in CI on every pull request
(see `.github/workflows/`). Findings from these tools are triaged as part
of normal review; if you believe CI is missing a real finding, a PR
enabling the relevant rule is welcome.
