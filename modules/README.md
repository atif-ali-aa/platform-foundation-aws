# modules/

Reusable, versioned Terraform modules. Every module here follows the same
contract: `main.tf`, `variables.tf` (with validation), `outputs.tf`, and a
`README.md` documenting inputs, outputs, and the design decisions behind
defaults. See [docs/terraform-standards.md](../docs/terraform-standards.md).

Modules are **Production-Ready** (fully implemented, reviewed, intended
for real use), **In Progress** (design/docs done, Terraform not written
yet), or **Planned** (interface and documentation only, no implementation,
see each module's README for what's missing). The full status table
lives in the root [README.md](../README.md).

| Module | Status |
| --- | --- |
| [`vpc`](vpc) | Production-Ready |
| [`iam`](iam) | Production-Ready |
| [`eks`](eks) | Production-Ready |
| [`acm`](acm) | Planned |
| [`route53`](route53) | Planned |
| [`secrets-manager`](secrets-manager) | Planned |
| [`cloudwatch`](cloudwatch) | Planned |
| [`kms`](kms) | Planned |
| [`s3-remote-state`](s3-remote-state) | Planned |
| [`ecr`](ecr) | Planned |
| [`waf`](waf) | Planned |
| [`eventbridge`](eventbridge) | Planned |
| [`sns`](sns) | Planned |
| [`sqs`](sqs) | Planned |

Karpenter is intentionally excluded. It's scoped as a future, separate
repository rather than a module here (see the EKS module README for why).
