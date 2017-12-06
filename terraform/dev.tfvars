environment = "Dev"
instance_type = "t2.medium"

vpc_id = "vpc-995b8fe0"  # pod-005
subnet_id = "subnet-4bb46d67"  # public subnet
security_group_ids = ["sg-abfcc1d5", "sg-a5d658d0", "sg-c5fec3bb"] 
# sg-abfcc1d5 - office ssh access
# sg-a5d658d0 - open http access to everyone
# sg-c5fec3bb - private SlaveSecurityGroup (open all acccess to all pod-005 SGs)

cname = "airflow.dev.forno.quintoandar.com.br"
hosted_zone_id = "Z36TQM3Q68J8QS"
certificate_arn = "arn:aws:acm:us-east-1:632540934959:certificate/7ac8b3a4-1fc7-437d-9735-5fb634dc8650"

# Forno VPC (it's open to the Pod005 cluster)
db_subnet_group = "default-vpc-7055f514"
db_vpc_security_group_ids = ["sg-8675bfe0"] # gives access to sg-c5fec3bb

s3_bucket = "5a-airflow-dev"
git_branch = "master"
