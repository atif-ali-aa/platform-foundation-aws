# vpc

Multi-AZ VPC foundation: public, private, and database subnet tiers,
NAT Gateway strategy, route tables, Network ACLs, a locked-down default
security group, and Kubernetes/EKS subnet tagging.

Design reasoning lives in [docs/networking.md](../../docs/networking.md)
and [ADR-005](../../docs/adr/ADR-005-why-multi-az-networking.md). This
README covers the module's actual inputs, outputs, and usage.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  environment = "prod"
  vpc_cidr    = "10.0.0.0/16"
  azs         = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnet_cidrs   = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs  = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
  database_subnet_cidrs = ["10.0.64.0/24", "10.0.65.0/24", "10.0.66.0/24"]

  single_nat_gateway = false # one NAT Gateway per AZ, see NAT strategy below
  eks_cluster_name   = "prod-eks"

  tags = {
    CostCenter = "platform"
  }
}
```

A dev/sandbox environment would typically set `single_nat_gateway = true`
and use only 2 AZs to reduce cost. See
[docs/cost-optimization.md](../../docs/cost-optimization.md).

## Design decisions

- **Three subnet tiers, replicated per AZ**: public (NAT gateways, load
  balancers), private (EKS node groups), database (isolated, no internet
  route). See [docs/networking.md](../../docs/networking.md#subnet-tiers).
- **NAT strategy is a variable, not a constant.** `single_nat_gateway`
  defaults to `false` (one NAT Gateway per AZ) because a production
  default silently choosing the cheaper, less resilient option is worse
  than an environment being slightly more expensive than necessary. Dev
  environments opt into the shared NAT explicitly.
- **Private route tables are per-AZ**, each routing to the NAT Gateway in
  the same AZ (or to the single shared one, if `single_nat_gateway` is
  true), so one AZ's NAT failure doesn't take down another AZ's egress.
- **Database subnets have no default route at all.** This isn't a
  security group blocking egress, it's an actual absence of a route to
  any gateway. Reaching them requires being inside the VPC.
- **Network ACLs are a subnet-level backstop, not the primary control.**
  Public allows 80/443 inbound plus ephemeral return traffic. Private
  allows all traffic from the VPC CIDR (which covers NAT Gateway return
  traffic, since NAT rewrites the source to an address inside the VPC).
  Database allows traffic only from the VPC CIDR, in both directions.
  Security groups on the actual workloads remain how per-service access
  is scoped. See [docs/networking.md](../../docs/networking.md#security-groups-vs-network-acls).
- **The VPC's default security group is locked down to deny all
  traffic.** This is a deliberate, managed resource
  (`aws_default_security_group`), not an oversight. Nothing should ever
  end up attached to the implicit default group and inherit whatever
  rules happen to be on it.
- **Kubernetes subnet tagging is always applied to public/private
  subnets** (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`)
  so the AWS Load Balancer Controller can discover them regardless of
  whether `eks_cluster_name` is set. The cluster-specific
  `kubernetes.io/cluster/<name>` tag is only added when
  `eks_cluster_name` is provided, since an empty/placeholder cluster name
  tag would be actively misleading.
- **A database subnet group is created by default** (`aws_db_subnet_group`,
  gated by `create_database_subnet_group`) since almost anything landing
  in the database tier (RDS, ElastiCache, DocumentDB) needs one, and
  hand-writing the same subnet group in every environment that consumes
  this module would be pure duplication.

## Reviewed CI exceptions

Two `checkov` findings are suppressed inline (`# checkov:skip=...` in
`main.tf`) rather than left to silently fail CI or globally disabled.
See [docs/security.md](../../docs/security.md#ci-enforced-scanning) for
the exception policy:

- **`CKV_AWS_130`** on `aws_subnet.public`: auto-assigning public IPs is
  the defining characteristic of the public tier (NAT gateways, load
  balancers). The private and database subnets do not set this.
- **`CKV2_AWS_11`** on `aws_vpc.this`: VPC Flow Logs are deferred to the
  planned `cloudwatch` module rather than duplicating log-destination
  wiring here (see "What this module deliberately does not do" below).

## What this module deliberately does not do

- No VPC endpoints (S3, ECR, CloudWatch Logs, etc.). This is a real cost
  and security optimization, but it's layered on top once there's actual
  NAT traffic to measure. See
  [docs/cost-optimization.md](../../docs/cost-optimization.md).
- No VPC Flow Logs. Tracked as a gap, not silently assumed. Add via the
  planned `cloudwatch` module once it exists rather than bolting
  observability concerns onto the networking module.
- No transit gateway / VPC peering. Out of scope for a single-account
  platform foundation; revisit if or when a multi-account design is
  needed.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `environment` | Deployment environment name (`dev`, `staging`, `prod`). Used in naming/tagging. | `string` | n/a | yes |
| `vpc_cidr` | IPv4 CIDR block for the VPC. | `string` | n/a | yes |
| `azs` | Availability Zones to deploy subnets into. Minimum 2. | `list(string)` | n/a | yes |
| `public_subnet_cidrs` | CIDR blocks for public subnets, one per AZ. | `list(string)` | n/a | yes |
| `private_subnet_cidrs` | CIDR blocks for private subnets, one per AZ. | `list(string)` | n/a | yes |
| `database_subnet_cidrs` | CIDR blocks for database subnets, one per AZ. | `list(string)` | n/a | yes |
| `single_nat_gateway` | Use one shared NAT Gateway instead of one per AZ. | `bool` | `false` | no |
| `eks_cluster_name` | EKS cluster name for the `kubernetes.io/cluster/<name>` subnet tag. | `string` | `null` | no |
| `create_database_subnet_group` | Whether to create an `aws_db_subnet_group`. | `bool` | `true` | no |
| `tags` | Additional tags merged into every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| --- | --- |
| `vpc_id` | ID of the VPC. |
| `vpc_cidr_block` | CIDR block of the VPC. |
| `internet_gateway_id` | ID of the Internet Gateway. |
| `public_subnet_ids` | IDs of the public subnets. |
| `private_subnet_ids` | IDs of the private subnets. |
| `database_subnet_ids` | IDs of the database subnets. |
| `database_subnet_group_name` | Name of the database subnet group, or `null`. |
| `public_route_table_id` | ID of the shared public route table. |
| `private_route_table_ids` | IDs of the per-AZ private route tables. |
| `database_route_table_id` | ID of the shared database route table. |
| `nat_gateway_ids` | IDs of the NAT Gateways. |
| `nat_gateway_public_ips` | Public IPs of the NAT Gateways. |
| `default_security_group_id` | ID of the locked-down default security group. |
| `azs` | Availability Zones used, passed through for downstream modules. |
