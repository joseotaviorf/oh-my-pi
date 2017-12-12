################################################
## NOTE: default values for FORNO environment ##
################################################

variable "environment" {
  default = "Forno"
}

# Provider configuration
variable "aws_region" {
  default = "us-east-1"
}

# EC2 configuration
variable "key_name" {
  default = "5a-airflow"
}
variable "instance_type" {
  default = "r4.large"
}
variable "instance_name" {
  default = "Airflow"
}

# Tags
variable "tag_service" {
  default = "Airflow"
}
variable "tag_owner" {
  default = "Data"
}
variable "tag_business_unit" {
  default = "Data"
}

# Network
variable "vpc_id" {
    default = "vpc-7055f514"
}
variable "subnet_id" {
    default = "subnet-747f545f"
}
variable "security_group_ids" {
    default = ["sg-8675bfe0"]
}

# Distribution
variable "hosted_zone_id" {
    default = "Z36TQM3Q68J8QS"
}
variable "cname" {
    default = "airflow.forno.quintoandar.com.br"
}
variable "certificate_arn" {
    default = "arn:aws:acm:us-east-1:632540934959:certificate/7ac8b3a4-1fc7-437d-9735-5fb634dc8650"
}

# Database
variable "db_username" {}
variable "db_password" {}
variable "db_instance_type" {
    default = "db.t2.micro"
}
variable "db_subnet_group" {
    default = "default-vpc-7055f514"
}
variable "db_vpc_security_group_ids" {
    default = ["sg-8675bfe0"]
}
variable "db_allocated_storage" {
  default = 10
}

# S3 Log folder
variable "s3_bucket" {
    "default" = "airflow.forno"
}

variable "s3_key" {}
variable "s3_secret" {}

# Google OAuth Credentials
variable "google_client_id" {}
variable "google_client_secret" {}

# GitHub info (used only once to clone bi-etl-juice)
variable "git_private_key_file" {}
variable "git_branch" {
    default = "master"
}

# Sentry configuration
variable "sentry_dsn" {}

# New Relic configuration
variable "nr_license_key" {}

# Unique fernet key for database encryption:
#
#   IMPORTANT: this is required to connect to an existing database! E.g. should
#   you need to spin up a new Airflow installation but want to connect to a
#   database used by a previous installation, make sure that the fernet_key
#   remains the same!
variable "fernet_key" {}
