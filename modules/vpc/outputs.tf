output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in the same order as the azs input."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, in the same order as the azs input."
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs of the database subnets, in the same order as the azs input."
  value       = aws_subnet.database[*].id
}

output "database_subnet_group_name" {
  description = "Name of the database subnet group, or null if create_database_subnet_group is false."
  value       = var.create_database_subnet_group ? aws_db_subnet_group.database[0].name : null
}

output "public_route_table_id" {
  description = "ID of the shared public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables, one per AZ, in the same order as the azs input."
  value       = aws_route_table.private[*].id
}

output "database_route_table_id" {
  description = "ID of the shared database route table."
  value       = aws_route_table.database.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways. One entry if single_nat_gateway is true, otherwise one per AZ."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "Public (Elastic) IPs of the NAT Gateways."
  value       = aws_eip.nat[*].public_ip
}

output "default_security_group_id" {
  description = "ID of the VPC's default security group, managed here to deny all traffic by default."
  value       = aws_default_security_group.this.id
}

output "azs" {
  description = "Availability Zones used by this VPC, passed through for convenience when wiring this module's outputs into the iam/eks modules."
  value       = var.azs
}
