# Networking

Design reasoning for the `vpc` module. For the visual layout, see
[aws-networking.md](../architecture/aws-networking.md); for why multi-AZ
is the default at all, see
[ADR-005](adr/ADR-005-why-multi-az-networking.md).

## Subnet tiers

Three tiers, each replicated per Availability Zone:

| Tier | Purpose | Default route |
| --- | --- | --- |
| Public | NAT gateways, internet-facing load balancers | `0.0.0.0/0` → Internet Gateway |
| Private | EKS node groups, internal workloads | `0.0.0.0/0` → NAT Gateway (same AZ) |
| Database | Data stores with no direct internet path | No default route |

The database tier having no default route is a deliberate constraint, not
a placeholder for "add a route later." Anything in that tier that needs
outbound access to an AWS-managed service should go through a VPC
endpoint, not a NAT route added as an exception.

## CIDR sizing

CIDR ranges are module inputs, not hardcoded. The default sizing assumes:

- Private subnets sized generously enough for EKS's `AmazonVPCCNI` pod
  networking (each node reserves IPs for the pods it can run, which adds
  up fast on m5.xlarge-class nodes and above without prefix delegation
  enabled).
- Public subnets sized for NAT gateways and load balancer ENIs, small
  relative to private subnets.
- Database subnets sized for the data stores actually planned, not
  padded arbitrarily.

Getting this wrong doesn't fail loudly. It fails months later when a
node group can't scale because the subnet ran out of IPs. See the `vpc`
module README for the exact default CIDR blocks and how to size them for
a given expected node/pod count.

## NAT strategy

`single_nat_gateway` is a module input. One shared NAT gateway is cheaper
and appropriate for dev/sandbox environments; one NAT gateway per AZ is
the production default. This is documented in
[cost-optimization.md](cost-optimization.md) and
[ADR-005](adr/ADR-005-why-multi-az-networking.md). The module doesn't
silently pick the cheap option for you, because a production environment
that ends up on a single shared NAT because nobody set the flag is a
worse outcome than an environment that's slightly more expensive than it
needed to be.

## Security groups vs. Network ACLs

Both exist in the module, with different jobs:

- **Security groups** are the primary, workload-facing control: stateful,
  attached to ENIs, expected to be scoped per workload (a node group's
  security group, a database's security group), not one broad group
  everything shares.
- **Network ACLs** are a coarser, subnet-level backstop: stateless,
  evaluated before security groups, useful for an explicit deny (e.g.
  blocking a known-bad CIDR range at the subnet boundary) that shouldn't
  depend on every security group being configured correctly. They are
  not a substitute for correct security group scoping. Treating NACLs as
  the primary control tends to produce rules nobody can reason about
  because stateless rules require matching both directions explicitly.

## Kubernetes subnet tagging

EKS's cluster autoscaler and the AWS Load Balancer Controller discover
subnets by tag, not by explicit ID configuration in most setups. The
`vpc` module applies:

- `kubernetes.io/cluster/<cluster-name> = shared` (or `owned`) on subnets
  meant to be used by that cluster
- `kubernetes.io/role/elb = 1` on public subnets (external load balancers)
- `kubernetes.io/role/internal-elb = 1` on private subnets (internal load
  balancers)

Getting these tags wrong doesn't fail at `terraform apply`. It fails
later when the AWS Load Balancer Controller can't find a subnet to place
an ALB in, which is a much harder failure to trace back to a Terraform
tag. See the `vpc` module README for the exact tag reference once it
ships.

## Production tagging strategy

Beyond the Kubernetes-specific tags above, every resource the `vpc`
module creates carries a consistent tag set (`Environment`, `ManagedBy`,
`Module`, plus any caller-supplied tags merged in). See
[repository-standards.md](repository-standards.md#tagging-strategy) for
the full convention shared across all modules, not just `vpc`.
