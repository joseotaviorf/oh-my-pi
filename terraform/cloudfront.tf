resource "aws_cloudfront_distribution" "airflow" {
  aliases     = ["${var.cname}"]

  origin {
    domain_name = "${aws_instance.airflow.public_dns}"
    origin_id   = "${format("%s-%s", "airflow", lower(var.environment))}"

    custom_origin_config = {
        http_port = 80
        https_port = 443
        origin_ssl_protocols = ["SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2"]
        origin_protocol_policy = "http-only"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${format("%s-%s", "airflow", lower(var.environment))}"

    forwarded_values {
      query_string = true
      headers = ["*"] # very important!
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  enabled             = true
  is_ipv6_enabled     = true

  price_class = "PriceClass_All"

  viewer_certificate {
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
    acm_certificate_arn = "${var.certificate_arn}"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags {
    Environment   = "${var.environment}"
    Service       = "${var.tag_service}"
    Owner         = "${var.tag_owner}"
    Business_Unit = "${var.tag_business_unit}"
  }
}

output "cloudfront-id" {
  value = "${aws_cloudfront_distribution.airflow.id}"
}
