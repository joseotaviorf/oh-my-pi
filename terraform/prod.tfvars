environment = "Prod"
instance_type = "r4.large"

vpc_id = "vpc-9fa27ee6" # pod-006
subnet_id = "subnet-39dc0163"  # public subnet
security_group_ids = ["sg-31a43244", "sg-cac0c9b4", "sg-bfcfc6c1"]
# sg-cac0c9b4 - office ssh access
# sg-31a43244 - open http access to everyone
# sg-bfcfc6c1 - private SlaveSecurityGroup (open all acccess to all pod-006 SGs)

cname = "airflow.quintoandar.com.br"
hosted_zone_id = "Z3K9RABD1G3B35"
certificate_arn = "arn:aws:acm:us-east-1:632540934959:certificate/200348a2-647d-4d38-8b56-2f108c252b87"

db_instance_type = "db.t2.small"
db_allocated_storage = "20"
db_subnet_group = "vpc default" # bds production subnet group
db_vpc_security_group_ids = ["sg-e8c8998c"] # gives acces to sg-bfcfc6c1

s3_bucket = "5a-airflow"
