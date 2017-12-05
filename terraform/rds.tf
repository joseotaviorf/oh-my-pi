resource "aws_db_instance" "airflow" {
  allocated_storage       = "${var.db_allocated_storage}"
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "5.6.37"
  instance_class          = "${var.db_instance_type}"
  identifier              = "${format("%s-%s", "airflow", lower(var.environment))}"
  parameter_group_name    = "default.mysql5.6"
  name                    = "airflow"
  username                = "${var.db_username}"
  password                = "${var.db_password}"
  db_subnet_group_name    = "${var.db_subnet_group}"
  vpc_security_group_ids  = "${var.db_vpc_security_group_ids}"
  skip_final_snapshot     = true
  publicly_accessible     = false

  tags {
    Environment   = "${var.environment}"
    Service       = "${var.tag_service}"
    Owner         = "${var.tag_owner}"
    Business_Unit = "${var.tag_business_unit}"
  }
}

output "db_endpoint" {
  value = "${aws_db_instance.airflow.endpoint}"
}
