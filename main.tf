/**
 * 
 * AWS VPC Peering Connection Module
 * =================================
 * 
 * Terraform module, which creates a peering connection between two VPCs and adds routes to the local VPC.
 * 
 * Usage
 * -----
 * 
 * ### Single Region Peering
 * **Notice**: You need to declare both providers even with single region peering.
 * 
 * ```hc1
 * module "vpc_single_region_peering" {
 *   source = "dcos-terraform/vpc-peering/aws"
 * 
 *   providers = {
 *     aws.local = "aws"
 *     aws.remote = "aws"
 *   }
 *
 *   remote_vpc_id              = "vpc-bbbbbbbb"
 *   remote_cidr_block          = "10.0.0.0/16"
 *   remote_main_route_table_id = "rtb-aaaaaaaa"
 *   remote_security_group_id   = "sg-11111111"
 *   local_cidr_block          = "10.1.0.0/16"
 *   local_main_route_table_id = "rtb-bbbbbbbb"
 *   local_security_group_id   = "sg-00000000"
 *   local_vpc_id              = "vpc-aaaaaaaa"
 *
 *   tags = {
 *     Environment = "prod"
 *   }
 * }
 * ```
 * 
 * ### Cross Region Peering
 * 
 * ```hc1
 * module "vpc_cross_region_peering" {
 *   source = "dcos-terraform/vpc-peering/aws"
 * 
 *   providers = {
 *     aws.local = "aws.src"
 *     aws.remote = "aws.dst"
 *   }
 *
 *   remote_vpc_id              = "vpc-bbbbbbbb"
 *   remote_cidr_block          = "10.0.0.0/16"
 *   remote_main_route_table_id = "rtb-aaaaaaaa"
 *   remote_security_group_id   = "sg-11111111"
 *   local_cidr_block          = "10.1.0.0/16"
 *   local_main_route_table_id = "rtb-bbbbbbbb"
 *   local_security_group_id   = "sg-00000000"
 *   local_vpc_id              = "vpc-aaaaaaaa"
 *
 *   tags = {
 *     Environment = "prod"
 *   }
 * }
 *```
 */

# Providers are required because of cross-region
provider "aws" {
  alias = "local"
}

provider "aws" {
  alias = "remote"
}

data "aws_caller_identity" "current" {}

data "aws_region" "remote" {
  provider = "aws.remote"
}

data "aws_route_table" "local_vpc_rt" {
  provider = "aws.local"
  vpc_id   = "${var.local_vpc_id}"
}

data "aws_route_table" "remote_vpc_rt" {
  provider = "aws.remote"
  vpc_id   = "${var.remote_vpc_id}"
}

# Create a route
resource "aws_route" "local_rt" {
  provider                  = "aws.local"
  route_table_id            = "${coalesce(var.local_main_route_table_id, data.aws_route_table.local_vpc_rt.id)}"
  destination_cidr_block    = "${var.remote_cidr_block}"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.peering.id}"
}

## Create a route
resource "aws_route" "remote_rt" {
  provider                  = "aws.remote"
  route_table_id            = "${coalesce(var.remote_main_route_table_id, data.aws_route_table.remote_vpc_rt.id)}"
  destination_cidr_block    = "${var.local_cidr_block}"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.peering.id}"
}

resource "aws_vpc_peering_connection" "peering" {
  provider    = "aws.local"
  vpc_id      = "${var.local_vpc_id}"
  peer_vpc_id = "${var.remote_vpc_id}"
  peer_region = "${data.aws_region.remote.name}"

  tags = "${merge(var.tags, map("Name", "VPC Peering between default and bursting"))}"
}

# Accepter's side of the connection.
resource "aws_vpc_peering_connection_accepter" "remote" {
  provider                  = "aws.remote"
  vpc_peering_connection_id = "${aws_vpc_peering_connection.peering.id}"
  auto_accept               = true

  tags = "${merge(var.tags, map("Name", "Accepter"))}"
}

resource "aws_security_group_rule" "local_sg" {
  provider    = "aws.local"
  type        = "ingress"
  from_port   = 0
  to_port     = 65535
  protocol    = "all"
  cidr_blocks = ["${var.remote_cidr_block}"]

  security_group_id = "${var.local_security_group_id}"
}

resource "aws_security_group_rule" "remote_sg" {
  provider    = "aws.remote"
  type        = "ingress"
  from_port   = 0
  to_port     = 65535
  protocol    = "all"
  cidr_blocks = ["${var.local_cidr_block}"]

  security_group_id = "${var.remote_security_group_id}"
}
