from bietlejuice.jobs.composer.loaders.hive_metastore_loader import HiveMetastoreLoader
from bietlejuice.jobs.composer.loaders.redshift_loader import RedshiftLoader
from bietlejuice.jobs.composer.loaders.spark_metastore_loader import (
    SparkMetastoreLoader,
)

# Removing the import of S3Loader since it imports the SparkContext automatically
# This is crashing some parallel processing in Spark
# https://stackoverflow.com/questions/52033611/sparkcontext-can-only-be-used-on-the-driver
# from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
