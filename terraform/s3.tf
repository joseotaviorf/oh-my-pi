resource "aws_s3_bucket" "airflow" {
  bucket = "${var.s3_bucket}"
  acl    = "private"

  tags {
    Name          = "${var.instance_name}"
    Environment   = "${var.environment}"
    Service       = "${var.tag_service}"
    Owner         = "${var.tag_owner}"
    Business_Unit = "${var.tag_business_unit}"
  }
}
