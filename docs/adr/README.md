# Architecture Decision Records

An ADR is written when a decision is expensive to reverse. It changes the
shape of every module built on top of it, or it trades off something a
future reader would otherwise have to rediscover the hard way. Not every
choice gets one; picking a variable name doesn't need a paper trail,
picking Terraform over CDK does.

Each ADR follows the same structure: **Problem**, **Decision**,
**Trade-offs**, **Alternatives**, **Production considerations**. If a
decision is later reversed, add a new ADR that supersedes the old one
rather than editing history. The old ADR stays as a record of what was
believed true at the time and why it changed.

| ADR | Title | Status |
| --- | --- | --- |
| [ADR-001](ADR-001-why-terraform.md) | Why Terraform | Accepted |
| [ADR-002](ADR-002-why-amazon-eks.md) | Why Amazon EKS | Accepted |
| [ADR-003](ADR-003-why-gitops.md) | Why GitOps-Ready (Not GitOps-Included) | Accepted |
| [ADR-004](ADR-004-why-irsa.md) | Why IRSA | Accepted |
| [ADR-005](ADR-005-why-multi-az-networking.md) | Why Multi-AZ Networking | Accepted |
