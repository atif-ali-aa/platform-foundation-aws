variable "environment" {
  description = "Deployment environment name. Used in resource naming, tagging, and to gate production-only defaults (e.g. NAT strategy)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC. Must be large enough to fit public, private, and database subnets across every AZ in azs."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "Availability Zones to deploy subnets into. At least 2 are required for the multi-AZ design this module implements (see docs/adr/ADR-005-why-multi-az-networking.md); 3 is the production default."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "azs must contain at least 2 Availability Zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per entry in azs, in the same order."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must have exactly one entry per AZ in azs."
  }

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "each entry in public_subnet_cidrs must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS node groups, internal workloads), one per entry in azs, in the same order."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must have exactly one entry per AZ in azs."
  }

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "each entry in private_subnet_cidrs must be a valid IPv4 CIDR block."
  }
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets (no route to the internet), one per entry in azs, in the same order."
  type        = list(string)

  validation {
    condition     = length(var.database_subnet_cidrs) == length(var.azs)
    error_message = "database_subnet_cidrs must have exactly one entry per AZ in azs."
  }

  validation {
    condition     = alltrue([for c in var.database_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "each entry in database_subnet_cidrs must be a valid IPv4 CIDR block."
  }
}

variable "single_nat_gateway" {
  description = "Use a single, shared NAT Gateway for all private subnets instead of one per AZ. Cheaper, but a single point of failure for outbound traffic. Appropriate for dev/sandbox, not recommended for staging/prod. See docs/adr/ADR-005-why-multi-az-networking.md and docs/cost-optimization.md."
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster that will use these subnets, used to apply the kubernetes.io/cluster/<name> discovery tag to public and private subnets. Leave null if no EKS cluster consumes this VPC yet."
  type        = string
  default     = null
}

variable "create_database_subnet_group" {
  description = "Whether to create an aws_db_subnet_group spanning the database subnets, for use by RDS, ElastiCache, DocumentDB, etc."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags merged into every resource this module creates, on top of the standard Environment/ManagedBy/Module/Repository tags (see docs/repository-standards.md)."
  type        = map(string)
  default     = {}
}
