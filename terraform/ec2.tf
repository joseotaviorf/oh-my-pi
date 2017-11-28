provider "aws" {
  region  = "${var.aws_region}"
}

data "aws_ami" "amazon" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*"]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  owners = ["137112412989"] # Amazon
}

resource "aws_iam_instance_profile" "airflow" {
  name = "${format("%s-%s", "AirflowProfile", var.environment)}"
  role = "${aws_iam_role.airflow.name}"
}

resource "aws_instance" "airflow" {
  depends_on = ["aws_cloudwatch_log_group.airflow", "aws_s3_bucket.airflow"]

  ami                         = "${data.aws_ami.amazon.id}"
  instance_type               = "${var.instance_type}"
  key_name                    = "${var.key_name}"
  subnet_id                   = "${var.subnet_id}"
  vpc_security_group_ids      = "${var.security_group_ids}"
  associate_public_ip_address = true
  iam_instance_profile = "${aws_iam_instance_profile.airflow.name}"

  user_data = "${file("user-data.yml")}"

  tags {
    Name          = "${var.instance_name}"
    Environment   = "${var.environment}"
    Service       = "${var.tag_service}"
    Owner         = "${var.tag_owner}"
    Business_Unit = "${var.tag_business_unit}"
  }

  # This is where we configure the instance with ansible-playbook
  provisioner "local-exec" {
      command = <<EOF
        sleep 120; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -u airflow \
        -i '${aws_instance.airflow.public_ip},' \
        --extra-vars "server_name='${var.cname}'" \
        --extra-vars "log_group='${aws_cloudwatch_log_group.airflow.name}'" \
        --extra-vars "s3_bucket='${var.s3_bucket}'" \
        --extra-vars "s3_key='${var.s3_key}'" \
        --extra-vars "s3_secret='${var.s3_secret}'" \
        --extra-vars "google_client_id='${var.google_client_id}'" \
        --extra-vars "google_client_secret='${var.google_client_secret}'" \
        --extra-vars "db_username='${var.db_username}'" \
        --extra-vars "db_password='${var.db_password}'" \
        --extra-vars "db_name='${aws_db_instance.airflow.name}'" \
        --extra-vars "db_hostname='${aws_db_instance.airflow.endpoint}'" \
        --extra-vars "git_branch='${var.git_branch}'" \
        --extra-vars "git_private_key_file='${var.git_private_key_file}'" \
        airflow.yml
EOF
  }
}

output "instance-id" {
  value = "${aws_instance.airflow.id}"
}

output "instance-ip" {
  value = "${aws_instance.airflow.public_ip}"
}

output "instance-dns" {
  value = "${aws_instance.airflow.public_dns}"
}
