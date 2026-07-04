# ADR-005: Why Multi-AZ Networking

## Status

Accepted

## Problem

A single Availability Zone is a real, non-hypothetical failure domain.
AWS has had AZ-level outages before. An EKS cluster (and the ALBs,
databases, and NAT gateways it depends on) confined to one AZ goes down
with it. EKS itself also expects control-plane-adjacent subnets to span
multiple AZs; a single-AZ VPC fights the platform it's meant to host.

## Decision

The `vpc` module provisions three subnet tiers (public, private,
database), replicated across **three Availability Zones** by default
(configurable down to two for cost-constrained non-prod use, never to
one). NAT strategy is a configurable input (`single_nat_gateway`): one
shared NAT for dev/sandbox, one NAT per AZ for staging/production.

## Trade-offs

- **Per-AZ NAT gateways cost more.** Each NAT Gateway is billed hourly
  plus per-GB data processing, so three of them instead of one triples
  the fixed cost. A single shared NAT gateway is cheaper but becomes both
  a cross-AZ data transfer cost (traffic from AZ-b and AZ-c routing
  through a NAT in AZ-a) and a single point of failure for all outbound
  traffic.
- **More subnets means more CIDR planning up front.** Three tiers times
  three AZs is nine subnets per environment before any workload exists.
  CIDR sizing has to be decided deliberately (see
  [networking.md](../networking.md)) rather than grown into ad hoc later,
  or environments end up with inconsistent, hard-to-remember subnet
  layouts.
- **Database subnets with no NAT/IGW route add a step to any
  "just let this reach the internet" debugging session.** That's
  deliberate isolation, not an oversight, but it does mean a database
  needing an outbound connection (e.g. to a SaaS API) needs a
  VPC endpoint or explicit routing decision, not a default open route.

## Alternatives Considered

- **Single-AZ deployment**: cheapest, simplest CIDR plan, but a single
  AZ failure takes down the entire environment. Acceptable only for a
  genuinely disposable sandbox that isn't referenced anywhere else in
  this repository as a production pattern.
- **NAT instances instead of NAT Gateway**: cheaper per hour, but they're
  EC2 instances someone has to patch, scale, and fail over manually. AWS
  itself steers new deployments toward managed NAT Gateway. Reintroducing
  an unmanaged instance to save a small amount of money isn't a trade a
  production module should make by default.
- **VPC endpoints instead of NAT entirely**: reduces NAT data-processing
  cost for AWS-API-bound traffic (S3, ECR, CloudWatch), but doesn't
  eliminate the need for NAT if any workload needs general internet
  egress. Treated as a complementary, layerable optimization (see
  [cost-optimization.md](../cost-optimization.md)), not a substitute for
  the NAT strategy decided here.

## Production Considerations

- Default: 3 AZs, one NAT Gateway per AZ. `single_nat_gateway = true` is
  an explicit, documented opt-in for non-production environments, not
  the default a production `terraform apply` falls into silently.
- Subnets are tagged for Kubernetes/ALB auto-discovery
  (`kubernetes.io/role/elb` on public subnets,
  `kubernetes.io/role/internal-elb` on private subnets,
  `kubernetes.io/cluster/<cluster-name>` as required by the AWS Load
  Balancer Controller and Cluster Autoscaler). See the `vpc` module
  README for the exact tag set.
- Database subnets have route tables with no default route to an
  Internet Gateway or NAT Gateway. Reaching them requires being inside
  the VPC, by design.
- CIDR sizing is a module input, not a hardcoded constant, so an
  environment expecting more IPs per subnet (larger node groups, more
  pods with `AmazonVPCCNI` prefix delegation) isn't stuck re-architecting
  the VPC later.
