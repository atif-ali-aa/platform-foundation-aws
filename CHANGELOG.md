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
  subnet tagging, and a database subnet group. `terraform fmt` and
  `terraform validate` pass locally; `tflint`/`tfsec`/`checkov` were not
  runnable locally (not installed) but will run in CI. Two `checkov`
  findings are deliberately suppressed inline with justification. See
  `modules/vpc/README.md#reviewed-ci-exceptions`.
- `iam` module (Production-Ready): IAM OIDC provider, a generic IRSA role
  pattern (`irsa_roles`) with trust policies conditioned on both `sub`
  and `aud`, and three built-in example roles: External DNS (Route53,
  hosted-zone-scoped, no wildcard fallback), AWS Load Balancer Controller
  (modeled on the upstream policy structure, documented as needing
  version-specific verification), and Cluster Autoscaler (Auto Scaling
  actions scoped by the `k8s.io/cluster-autoscaler/<cluster>` resource
  tag). `terraform fmt` and `terraform validate` pass locally.
- `eks` module (Production-Ready): managed node groups (required, no
  hidden default), cluster/node IAM roles, production security groups
  (control plane to node rules per AWS's documented minimum), control
  plane logging to a Terraform-managed CloudWatch Logs group, EKS addons
  (`vpc-cni`, `coredns`, `kube-proxy`), modern Access Entry-based cluster
  access (no `aws-auth` ConfigMap), and a `cluster_oidc_issuer_url` output
  that feeds directly into the `iam` module for IRSA. Deliberately ships
  no Karpenter and no Helm/`kubernetes`-provider-based controller
  installs. See `modules/eks/README.md` for the reasoning and the exact
  Helm commands to run separately. `terraform fmt` and `terraform
  validate` pass locally. Two `checkov` findings are deliberately
  suppressed inline with justification. See
  `modules/eks/README.md#reviewed-ci-exceptions`.

<!--
Entries below this line are added as milestones complete. Each entry
should describe the module or capability that became available, not the
mechanics of how it was written.
-->
