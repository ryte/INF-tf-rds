locals {
  name = "${var.tags["Environment"]}-rds-${var.name}"
}

locals {
  short_name = "${substr("${local.name}", 0, min(20, length(local.name)))}",
  tags = "${merge(
    var.tags,
    map(
      "Module", "amicopy",
      "Name", "${local.name}"
    )
  )}"
}
