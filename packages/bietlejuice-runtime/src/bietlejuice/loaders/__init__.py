from bietlejuice.loaders.glue_metastore_loader import GlueMetastoreLoader
from bietlejuice.loaders.hive_metastore_loader import HiveMetastoreLoader
from bietlejuice.loaders.redshift_loader import RedshiftLoader
from bietlejuice.loaders.spark_metastore_loader import SparkMetastoreLoader

__all__ = [
    "GlueMetastoreLoader",
    "HiveMetastoreLoader",
    "RedshiftLoader",
    "SparkMetastoreLoader",
]

# Removing the import of S3Loader since it imports the SparkContext automatically
# This is crashing some parallel processing in Spark
# https://stackoverflow.com/questions/52033611/sparkcontext-can-only-be-used-on-the-driver
# from bietlejuice.loaders.s3_loader import S3Loader
