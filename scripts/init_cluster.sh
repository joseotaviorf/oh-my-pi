#! /bin/bash

# This script is used for initializing clusters dependencies in Databricks
# and it is manually placed inside 5a-artifacts/bi-etl-ejuice

echo "Downgrading pip"
/databricks/python/bin/pip install pip==18.1
/databricks/python/bin/pip install amqp==2.6.1
