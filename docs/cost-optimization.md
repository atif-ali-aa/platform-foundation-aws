# Cost Optimization

Where this platform spends money by default, and the levers each module
exposes to reduce it. Written so a cost review doesn't have to
reverse-engineer intent from Terraform defaults.

## NAT gateways

The single biggest fixed networking cost. Production default is one NAT
gateway per AZ (three, at default subnet count) for the resiliency
reasons in [ADR-005](adr/ADR-005-why-multi-az-networking.md). Each one
bills hourly plus per-GB data processing.

- **Lever**: `single_nat_gateway = true` on the `vpc` module collapses
  this to one shared NAT gateway. Appropriate for dev/sandbox
  environments where an AZ-level NAT outage taking down all outbound
  traffic is an acceptable risk, not appropriate for anything called
  staging or prod in this repository's environment layout.
- **Complementary, not a substitute**: VPC endpoints for AWS-managed
  services (S3, ECR, CloudWatch Logs) remove that traffic from the NAT
  data-processing bill entirely, regardless of NAT strategy. This is a
  layerable optimization worth adding once workloads are actually
  generating S3/ECR traffic through NAT. It's premature to guess at
  before there's real traffic to measure.

## EKS control plane

Flat per-cluster-hour cost regardless of size (see
[ADR-002](adr/ADR-002-why-amazon-eks.md)), not something a Terraform
default can reduce. The lever here is consolidation: fewer, larger
clusters shared across workloads cost less in control-plane fees than
many small single-purpose clusters, at the expense of blast radius and
multi-tenancy isolation work. This repository doesn't prescribe a
cluster-per-environment-vs-shared-cluster answer. That's an
organizational trade-off `environments/` should make explicit per
deployment, not a default baked into the `eks` module.

## Node groups

- Managed node groups scale via Cluster Autoscaler, not a fixed node
  count sized for peak load year-round. Under-provisioning min/max bounds
  defeats this; over-provisioning them (setting `min_size` close to
  `max_size` "to be safe") defeats it just as effectively by keeping
  nodes running that autoscaling would otherwise have scaled down.
- Instance type selection is a module input, not hardcoded. Right-sizing
  for actual workload CPU/memory shape matters more here than any
  Terraform-level toggle can.
- **Spot capacity and more granular bin-packing** are real cost levers
  but are explicitly the domain of a future Karpenter-based
  repository/module, not this one. See
  [ADR-002](adr/ADR-002-why-amazon-eks.md) for why Karpenter isn't bolted
  onto the `eks` module here. Cluster Autoscaler with managed node groups
  is the production-ready path today; it's a smaller cost-optimization
  surface than Karpenter by design, not by oversight.

## Logging and observability

EKS control plane logging (API server, audit, authenticator) to
CloudWatch Logs has real per-GB ingestion and storage cost, especially
with audit logs enabled at high verbosity on a busy cluster. Retention
period is a module input specifically so it's a deliberate choice
(shorter retention for dev, longer for prod compliance needs) rather
than a single default that's wrong for half the environments using it.
Centralized, cross-account log aggregation is tracked under the Planned
`cloudwatch` module rather than assumed to exist.

## Tagging for cost allocation

Every resource carries `Environment` and `Module` tags (see
[repository-standards.md](repository-standards.md#tagging-strategy)).
This is what makes a Cost Explorer or Cost and Usage Report breakdown by
environment or module possible at all. A resource created without these
tags is invisible to that breakdown, which is why tagging is enforced at
the module level (every module applies a common tag map) rather than
left to each environment to remember.
