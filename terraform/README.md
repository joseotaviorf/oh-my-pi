# Deploy

Use Terraform and Ansible to deploy and configure the Airflow infrastructure. The terraform script will create:

* an EC2 instance
* a RDS database
* a Route53 record
* a Cloudfront distribution
* a CloudWatch log group
* a S3 bucket, for job logs (might want to replace by cloudwatch in the future)
* a IAM Role and Policy (to allow the instance to write to cloudwatch)

# Pre-requisites

* Terraform
* Ansible
* Existing AWS VPC, Subnet and Security Groups
* Existing AWS Key-Pair
* Existing Google Cloud Credentials (for OAuth)
* A deploy key for bi-etl-ejuice repository

### Security Groups

The EC2 instance should have the following inbound permissions:

* http access from everywhere (so cloudfront can route https->http to the machine)
* ssh access from the continuous integration server, for remote update of dags
* (recommended) ssh access from the office, for maintenance

The RDS instance should have the following inbound permissions:

* :3306 access from the ec2 airflow instance
* (recommended) :3306 access from the office, for maintenance

### Google Cloud Credentials

This needs to be setup manually, ideally with a QuintoAndar Google administrative account (although for testing purposes any QuintoAndar Google account should do). The 'Authorized Redirect URIs' field should be of the form: `https://{airflow_url}/oauth2callback?next=%2Fadmin%2F`

See the [the docs](http://airflow.incubator.apache.org/security.html#google-authentication)) for more information.

When deployed, the server will be automatically configured with `AIRFLOW__GOOGLE__DOMAIN` set as `quintoandar.com.br`, to guarantee that only QuintoAndar users can access it.

### bi-etl-ejuice Deploy Key

A GitHub deploy key is used to give the airflow server access to the machine.

See [this tutorial](https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/) on how to generate a new key. Then access [bi-etl-ejuice repository](https://github.com/quintoandar/bi-etl-ejuice) adnministration panel and add it to the deploy keys. Finally just set the `git_private_key_file` terraform variable to the path of the private key.


# Usage

Use Terraform workspace to deploy the Airflow infrastructure accross environments.

### Private Key

This script requires ssh acccess to the deployed machine, to install Airflow remotely. This must be an existing key on AWS, and its name can be set on the
`secrets.tfvars` file (otherwise it will use the `5a-airflow` default).

Also make sure that you have added the private key to your ssh agent, e.g:

```
$ ssh-add ~/.ssh/5a-airflow.pem
```

### Secrets

You may use the secrets.tfvars file to add the required secrets (this file is ignored and changes will not be added to Git). Otherwise the script will prompt you fo the required variables.

### Examples

**Forno**

```
$ terraform workspace new forno  # run it only the first time
$ terraform workspace select forno
$ terraform apply -var-file=forno.tfvars -var-file=secrets.tfvars
```

**Prod**
```
$ terraform workspace new prod  # run it only the first time
$ terraform workspace select prod
$ terraform apply -var-file="prod.tfvars" -var-file="secrets.tfvars"
```
