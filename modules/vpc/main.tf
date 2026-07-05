terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

locals {
  name = "${var.environment}-vpc"

  default_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "vpc"
      Repository  = "platform-foundation-aws"
    },
    var.tags,
  )

  az_count          = length(var.azs)
  nat_gateway_count = var.single_nat_gateway ? 1 : local.az_count

  # kubernetes.io/cluster/<name> is only meaningful once a specific EKS
  # cluster is going to use these subnets, so it is omitted entirely
  # rather than applied with an empty/placeholder value when
  # eks_cluster_name is null.
  eks_cluster_tag = var.eks_cluster_name != null ? {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  } : {}
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

#tfsec:ignore:aws-ec2-require-vpc-flow-logs-for-all-vpcs
resource "aws_vpc" "this" {
  # checkov:skip=CKV2_AWS_11:VPC Flow Logs are deferred to the planned
  # cloudwatch module (see docs/cost-optimization.md and this module's
  # README) rather than duplicating log-destination wiring here.
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.default_tags, {
    Name = local.name
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.default_tags, {
    Name = "${local.name}-igw"
  })
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

#tfsec:ignore:aws-ec2-no-public-ip-subnet
resource "aws_subnet" "public" {
  # checkov:skip=CKV_AWS_130:Auto-assigning public IPs is the defining
  # characteristic of this module's public tier (NAT gateways, load
  # balancers). The private and database tiers below do not set this.
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.default_tags, local.eks_cluster_tag, {
    Name                     = "${var.environment}-vpc-public-${var.azs[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.default_tags, local.eks_cluster_tag, {
    Name                              = "${var.environment}-vpc-private-${var.azs[count.index]}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_subnet" "database" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.default_tags, {
    Name = "${var.environment}-vpc-database-${var.azs[count.index]}"
    Tier = "database"
  })
}

# ---------------------------------------------------------------------------
# NAT Gateways: one per AZ by default, or one shared gateway when
# single_nat_gateway is true. See docs/adr/ADR-005-why-multi-az-networking.md.
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.default_tags, {
    Name = "${local.name}-nat-eip-${var.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.default_tags, {
    Name = "${local.name}-nat-${var.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route Tables: public (one, shared across all public subnets)
# ---------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.default_tags, {
    Name = "${local.name}-public"
  })
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Route Tables: private, one per AZ so a NAT Gateway failure in one AZ
# doesn't take down another AZ's egress path.
# ---------------------------------------------------------------------------

resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.default_tags, {
    Name = "${local.name}-private-${var.azs[count.index]}"
  })
}

resource "aws_route" "private_nat_gateway" {
  count = local.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------------------------------------------------------------------------
# Route Table: database. Deliberately no default route to an Internet
# Gateway or NAT Gateway. See docs/networking.md.
# ---------------------------------------------------------------------------

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.default_tags, {
    Name = "${local.name}-database"
  })
}

resource "aws_route_table_association" "database" {
  count = local.az_count

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ---------------------------------------------------------------------------
# Network ACLs: a subnet-level backstop, not the primary control. Security
# groups (applied to workloads elsewhere) remain how per-workload access is
# actually scoped. See docs/networking.md.
# ---------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id

  tags = merge(local.default_tags, {
    Name = "${local.name}-public"
  })
}

#tfsec:ignore:aws-ec2-no-public-ingress-acl
resource "aws_network_acl_rule" "public_inbound_http" {
  # Public HTTP ingress is the defining purpose of this tier (internet-
  # facing load balancers); see docs/networking.md.
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

#tfsec:ignore:aws-ec2-no-public-ingress-acl
resource "aws_network_acl_rule" "public_inbound_https" {
  # Public HTTPS ingress is the defining purpose of this tier (internet-
  # facing load balancers); see docs/networking.md.
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

#tfsec:ignore:aws-ec2-no-public-ingress-acl
resource "aws_network_acl_rule" "public_inbound_ephemeral" {
  # checkov:skip=CKV_AWS_231:Ephemeral return-traffic ports (1024-65535)
  # are inherently a wide range covering ports like 3389 that this rule
  # is not actually opening for unsolicited access. NACLs are stateless,
  # so return traffic for connections nodes/NAT initiated has to be
  # allowed inbound on the full ephemeral range; the workload-facing
  # security groups (not this NACL) are the primary control that decides
  # what's actually reachable. See docs/networking.md.
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

#tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "public_outbound_all" {
  # Outbound-all matches the public tier's role (NAT gateways/ALBs
  # reaching arbitrary destinations); security groups on the actual
  # workloads remain the primary, per-port control. See docs/networking.md.
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.default_tags, {
    Name = "${local.name}-private"
  })
}

#tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "private_inbound_vpc" {
  # checkov:skip=CKV_AWS_352:All-ports is scoped to the VPC CIDR only
  # (not 0.0.0.0/0), covering intra-VPC pod/node traffic and NAT Gateway
  # return traffic whose ports aren't known in advance by a generic
  # module. This NACL is a subnet-level backstop; security groups on the
  # actual workloads are the primary, per-port control. See
  # docs/networking.md.
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port        = 0
}

#tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "private_outbound_all" {
  # Outbound-all matches node/NAT egress needs (arbitrary AWS API and
  # internet destinations); security groups on the actual workloads
  # remain the primary, per-port control. See docs/networking.md.
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

resource "aws_network_acl" "database" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.database[*].id

  tags = merge(local.default_tags, {
    Name = "${local.name}-database"
  })
}

#tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "database_inbound_vpc_only" {
  # checkov:skip=CKV_AWS_352:All-ports is scoped to the VPC CIDR only
  # (not 0.0.0.0/0). This module is engine-agnostic (RDS, ElastiCache,
  # DocumentDB all listen on different default ports), so the NACL can't
  # assume a specific port without being wrong for some engines. Per-port
  # scoping happens at the security group attached to the actual data
  # store, which is the primary control; see docs/networking.md.
  network_acl_id = aws_network_acl.database.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port        = 0
}

#tfsec:ignore:aws-ec2-no-excessive-port-access
resource "aws_network_acl_rule" "database_outbound_vpc_only" {
  # Same engine-agnostic reasoning as database_inbound_vpc_only above:
  # scoped to the VPC CIDR, not 0.0.0.0/0.
  network_acl_id = aws_network_acl.database.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port        = 0
}

# ---------------------------------------------------------------------------
# Default Security Group: locked down to deny all traffic. Nothing should
# rely on the account's implicit default security group. Every real
# workload gets its own purpose-scoped security group. See docs/security.md.
# ---------------------------------------------------------------------------

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.default_tags, {
    Name = "${local.name}-default-sg-locked-down"
  })

  # Intentionally no ingress/egress blocks. An empty default security
  # group denies all traffic.
}

# ---------------------------------------------------------------------------
# Database subnet group (RDS / ElastiCache / DocumentDB, etc.)
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "database" {
  count = var.create_database_subnet_group ? 1 : 0

  name       = "${local.name}-database"
  subnet_ids = aws_subnet.database[*].id

  tags = merge(local.default_tags, {
    Name = "${local.name}-database-subnet-group"
  })
}
