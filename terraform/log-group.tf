resource "aws_cloudwatch_log_group" "airflow" {
  name = "${format("/aws/ec2/airflow-%s/var/log/airflow", lower(var.environment))}"
  retention_in_days = 5

  tags {
    Environment   = "${var.environment}"
    Service       = "${var.tag_service}"
    Owner         = "${var.tag_owner}"
    Business_Unit = "${var.tag_business_unit}"
  }
}

output "cloudwatch-log-group" {
  value = "${aws_cloudwatch_log_group.airflow.name}"
}
