terraform {
  backend "s3" {
    bucket = "blackops-terraform-forno"
    key    = "airflow/state"
    region = "us-east-1"
    dynamodb_table = "blackops-terraform-forno"
  }
}
