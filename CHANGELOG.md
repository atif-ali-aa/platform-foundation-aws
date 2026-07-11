# Changelog

All notable changes to this repository are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning
intent is described in [docs/repository-standards.md](docs/repository-standards.md).

## [Unreleased]

### Added

- Repository scaffolding: governance files, community health files,
  `.editorconfig`, `.pre-commit-config.yaml`.
- CI: `terraform fmt`/`validate`/`tflint`/`tfsec`/`checkov` via a reusable
  workflow matrixed dynamically over any directory containing `.tf` files
  (`.github/workflows/terraform-ci.yml`), a separate `terraform plan`
  workflow scoped to `environments/**` once those exist
  (`.github/workflows/terraform-plan.yml`), and `markdownlint`
  (`.github/workflows/markdownlint.yml`).
- Documentation: 5 ADRs (`docs/adr/`) covering Terraform, EKS, GitOps
  scope, IRSA, and multi-AZ networking; 5 Mermaid architecture diagrams
  (`architecture/`); 8 engineering standards docs (`docs/*.md`) covering
  architecture, networking, Terraform standards, security, GitOps scope,
  cost optimization, repository standards, and operational guidelines.
- `vpc` module (Production-Ready): multi-AZ public/private/database
  subnets, configurable NAT strategy (per-AZ default, single shared for
  non-prod), per-AZ private route tables, isolated database route table,
  Network ACLs per tier, a locked-down default security group, EKS/ALB
  subnet tagging, and a database subnet group. Verified locally with
  `terraform fmt`/`validate`, `tflint`, `checkov`, and `tfsec` (the last
  two via Docker). Five `checkov` findings and ten `tfsec` findings are
  deliberately suppressed inline with justification. See
  `modules/vpc/README.md#reviewed-ci-exceptions`.
- `iam` module (Production-Ready): IAM OIDC provider, a generic IRSA role
  pattern (`irsa_roles`) with trust policies conditioned on both `sub`
  and `aud`, and three built-in example roles: External DNS (Route53,
  hosted-zone-scoped, no wildcard fallback), AWS Load Balancer Controller
  (modeled on the upstream policy structure, documented as needing
  version-specific verification), and Cluster Autoscaler (Auto Scaling
  actions scoped by the `k8s.io/cluster-autoscaler/<cluster>` resource
  tag). Verified locally with `terraform fmt`/`validate`, `tflint`,
  `checkov`, and `tfsec`; no findings.
- `eks` module (Production-Ready): managed node groups (required, no
  hidden default) attached to a launch template that enforces IMDSv2 and
  actually applies the node security group (EKS only auto-attaches the
  cluster's security groups to node ENIs otherwise), cluster/node IAM
  roles, production security groups (control plane to node rules per
  AWS's documented minimum), control plane logging to a Terraform-managed
  CloudWatch Logs group (365-day default retention, optional KMS key),
  EKS addons (`vpc-cni`, `coredns`, `kube-proxy`), modern Access
  Entry-based cluster access (no `aws-auth` ConfigMap), and a
  `cluster_oidc_issuer_url` output that feeds directly into the `iam`
  module for IRSA. Deliberately ships no Karpenter and no
  Helm/`kubernetes`-provider-based controller installs. See
  `modules/eks/README.md` for the reasoning and the exact Helm commands
  to run separately. Verified locally with `terraform fmt`/`validate`,
  `tflint`, `checkov`, and `tfsec`. Seven `checkov` findings and eleven
  `tfsec` findings are deliberately suppressed inline with justification.
  See `modules/eks/README.md#reviewed-ci-exceptions`.

### Fixed

- CI: the `tflint --init` step in `.github/workflows/reusable-terraform-checks.yml`
  was running without `--config`, so it silently initialized no plugins
  while the actual lint step (which does pass `--config`) then failed
  with `Plugin "aws" not found` on every module. Both steps now use the
  same config.
- `modules/eks`: `aws_security_group.node` was created but never actually
  attached to any node instance (EKS managed node groups only auto-attach
  the security groups passed into the cluster's `vpc_config`, not a
  standalone security group). Fixed by adding `aws_launch_template.node`
  with the node security group wired into `network_interfaces`; caught by
  `checkov`'s `CKV2_AWS_5` in CI, not by local review.
- `.github/PULL_REQUEST_TEMPLATE.md` and `CONTRIBUTING.md`: fixed a
  trailing-whitespace and a missing-code-fence-language markdownlint
  finding surfaced by the `Markdown Lint` workflow.
- CI: `aquasecurity/tfsec-action` in `reusable-terraform-checks.yml` made
  unauthenticated GitHub API calls to resolve its "latest" version and
  intermittently hit GitHub's shared rate limit for unauthenticated
  requests, failing `tfsec` on unrelated PRs (surfaced on two Dependabot
  PRs, unrelated to what either PR actually changed). Fixed by passing
  `github_token` to the action.
- CI: `terraform-plan.yml` and `markdownlint.yml` didn't trigger on
  changes to their own workflow file, so a Dependabot bump of an action
  version they use (`aws-actions/configure-aws-credentials`,
  `DavidAnson/markdownlint-cli2-action`) went completely unvalidated.
  Both workflows now trigger on changes to themselves.

<!--
Entries below this line are added as milestones complete. Each entry
should describe the module or capability that became available, not the
mechanics of how it was written.
-->
