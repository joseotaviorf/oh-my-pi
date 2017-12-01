resource "aws_route53_record" "airflow" {
    zone_id = "${var.hosted_zone_id}"
    name = "${var.cname}"
    type = "A"

    alias {
      name                   = "${aws_cloudfront_distribution.airflow.domain_name}"
      zone_id                = "${aws_cloudfront_distribution.airflow.hosted_zone_id}"
      evaluate_target_health = false
  }
}

resource "aws_route53_record" "airflow_ssh" {
    zone_id = "${var.hosted_zone_id}"
    name = "${format("%s.%s", "ssh", var.cname)}"

    type     = "CNAME"
    ttl      = "300"
    records  = ["${aws_instance.airflow.public_dns}"]
}

output "url" {
  value = "${aws_route53_record.airflow.name}"
}

output "ssh" {
  value = "${aws_route53_record.airflow_ssh.name}"
}

