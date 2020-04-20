data "aws_region" "current" {}

locals {
  "availability_zones" = "${formatlist("%s%s", data.aws_region.current.name, var.availability_zones)}"
}

provider "random" {
  version = "~> 1.1"
}

resource "random_pet" "instances" {
  count  = "${var.engine_mode != "serverless" ? length(var.instances) : 0 }"
  length = 1
}

resource "aws_rds_cluster_instance" "instance" {
  count = "${var.engine_mode != "serverless" ? length(var.instances) : 0 }"

  lifecycle {
    ignore_changes = ["identifier"]
  }

  tags                         = "${var.tags}"
  cluster_identifier           = "${aws_rds_cluster.cluster.id}"
  identifier                   = "${var.name}-${element(random_pet.instances.*.id, count.index)}"
  engine                       = "${var.engine}"
  engine_version               = "${var.engine_version}"
  instance_class               = "${element( split(":", element( var.instances, count.index ) ), 1 )}"
  promotion_tier               = "${element( split(":", element( var.instances, count.index ) ), 0 )}"
  preferred_maintenance_window = "${var.preferred_maintenance_window}"
  db_subnet_group_name         = "${aws_db_subnet_group.sng.id}"
  db_parameter_group_name      = "${var.db_instance_parameter_group_name}"

  apply_immediately = "${var.apply_immediately}"
}

resource "random_id" "final_snapshot" {
  prefix      = "${var.name}-final-snapshot-"
  byte_length = 8
}

resource "aws_rds_cluster" "cluster" {
  count = "${var.engine_mode != "serverless" ? 1 : 0}"

  lifecycle {
    ignore_changes = ["final_snapshot_identifier"]
  }

  tags                            = "${var.tags}"
  cluster_identifier              = "${var.name}"
  engine                          = "${var.engine}"
  engine_version                  = "${var.engine_version}"
  availability_zones              = ["${local.availability_zones}"]
  master_username                 = "${var.master_credentials["user"]}"
  master_password                 = "${var.master_credentials["password"]}"
  backup_retention_period         = "${var.backup_retention_period}"
  preferred_backup_window         = "${var.preferred_backup_window}"
  preferred_maintenance_window    = "${var.preferred_maintenance_window}"
  final_snapshot_identifier       = "${random_id.final_snapshot.hex}"
  vpc_security_group_ids          = ["${aws_security_group.sg.id}"]
  db_subnet_group_name            = "${aws_db_subnet_group.sng.id}"
  enabled_cloudwatch_logs_exports = "${var.cloudwatch_log_types}"
  apply_immediately               = "${var.apply_immediately}"
  backtrack_window                = "${var.backtrack_window}"
  storage_encrypted               = true
  db_cluster_parameter_group_name = "${var.db_cluster_parameter_group_name}"
}

resource "aws_rds_cluster" "serverless" {
  count = "${var.engine_mode == "serverless" ? 1 : 0}"

  lifecycle {
    ignore_changes = ["final_snapshot_identifier", "engine_version"]
  }

  tags                            = "${var.tags}"
  cluster_identifier              = "${var.name}"
  engine                          = "${var.engine}"
  engine_version                  = "${var.engine_version}"
  engine_mode                     = "serverless"
  availability_zones              = ["${local.availability_zones}"]
  master_username                 = "${var.master_credentials["user"]}"
  master_password                 = "${var.master_credentials["password"]}"
  backup_retention_period         = "${var.backup_retention_period}"
  preferred_backup_window         = "${var.preferred_backup_window}"
  preferred_maintenance_window    = "${var.preferred_maintenance_window}"
  final_snapshot_identifier       = "${random_id.final_snapshot.hex}"
  vpc_security_group_ids          = ["${aws_security_group.sg.id}"]
  db_subnet_group_name            = "${aws_db_subnet_group.sng.id}"
  apply_immediately               = "${var.apply_immediately}"
  backtrack_window                = "${var.backtrack_window}"
  storage_encrypted               = true
  db_cluster_parameter_group_name = "${var.db_cluster_parameter_group_name}"

  scaling_configuration {
    auto_pause               = "${var.auto_pause}"
    max_capacity             = "${var.max_capacity}"
    min_capacity             = "${var.min_capacity}"
    seconds_until_auto_pause = "${var.seconds_until_auto_pause}"
  }
}

resource "aws_db_subnet_group" "sng" {
  subnet_ids = ["${var.subnet_ids}"]
  tags       = "${merge(var.tags, map("Name", "${var.name}-subnet-group"))}"
}

resource "aws_security_group" "sg" {
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags   = "${merge(var.tags, map("Name", "${var.name}-sg"))}"
  vpc_id = "${var.vpc_id}"
}

resource "aws_security_group_rule" "sg_ingress" {
  type      = "ingress"
  from_port = "${var.engine_mode != "serverless" ? join(",",aws_rds_cluster.cluster.*.port) : join(",",aws_rds_cluster.serverless.*.port)}"
  to_port   = "${var.engine_mode != "serverless" ? join(",",aws_rds_cluster.cluster.*.port) : join(",",aws_rds_cluster.serverless.*.port)}"
  protocol  = "tcp"

  security_group_id        = "${aws_security_group.sg.id}"
  source_security_group_id = "${aws_security_group.intra.id}"
}

resource "aws_security_group" "intra" {
  tags   = "${merge(var.tags, map("Name", "${var.name}-intra"))}"
  vpc_id = "${var.vpc_id}"
}
