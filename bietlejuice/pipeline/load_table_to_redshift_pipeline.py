import boto3

from bietlejuice.clients.db_clients import SparkClient, PostgresClient
from bietlejuice.loaders import RedshiftLoader
from bietlejuice.pipeline.abstract_pipeline import AbstractPipeline
from bietlejuice.services import S3Service
from bietlejuice.services.metastore_services import SparkMetastoreService


class LoadTableToRedshiftPipeline(AbstractPipeline):
    """
    Class to load table to Redshift copying files from S3.
    """

    def __init__(
        self,
        spectrum_iam_role,
        redshift_connection,
        dw_bucket,
        dw_schema,
        source_schema,
        table_name,
    ):
        """
        :param spectrum_iam_role: spectrum iam role for Redshift
        :param redshift_connection: Redshift connection configurations
        :param dw_bucket: dw bucket to copy files from
        :param dw_schema: schema in Redshift
        :param source_schema: source database name in spark metastore
        :param table_name: table name to load
        """
        self.spectrum_iam_role = spectrum_iam_role
        self.redshift_connection = redshift_connection
        self.dw_bucket = dw_bucket
        self.dw_schema = dw_schema
        self.source_schema = source_schema
        self.table_name = table_name

    def run(self):
        """
        Execute logic to load table to Redshift.
        """
        s3_client = S3Service(boto3.resource("s3"))
        spark_metastore_service = SparkMetastoreService(SparkClient())

        redshift_client = PostgresClient(
            dbname=self.redshift_connection["db"],
            host=self.redshift_connection["host"],
            port=self.redshift_connection["port"],
            user=self.redshift_connection["user"],
            password=self.redshift_connection["pwd"],
            keepalives_idle=200,
        )

        redshift_loader = RedshiftLoader(
            self.spectrum_iam_role, redshift_client, s3_client, self.dw_bucket
        )

        redshift_loader.load_table_from_metastore(
            metastore_service=spark_metastore_service,
            source_schema=self.source_schema,
            source_table_name=self.table_name,
            target_schema=self.dw_schema,
            target_table_name=self.table_name,
            overwrite=True,
        )
