import json
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("RedshiftLoader")


class RedshiftLoader:
    COPY_COMMAND_TEMPLATE = """
    COPY {}.{}
    FROM '{}'
    IAM_ROLE '{}'
    FORMAT AS PARQUET
    MANIFEST;
    """
    MANIFEST_PATH_TEMPLATE = (
        "s3://{}/redshift-load-manifests/{}/{}/year={}/month={}/day={}/manifest.json"
    )
    IAM_ROLE = "arn:aws:iam::632540934959:role/SpectrumAccess"

    def __init__(self, redshift_client, s3_service, dw_bucket):
        self.redshift_client = redshift_client
        self.s3_service = s3_service
        self.dw_bucket = dw_bucket

    @staticmethod
    def _create_manifest_dict(files):
        return {
            "entries": [
                {"url": url, "mandatory": True, "meta": {"content_length": size}}
                for url, size in files
            ]
        }

    def _create_copy_command(self, schema, table, manifest_path):
        return self.COPY_COMMAND_TEMPLATE.format(
            schema, table, manifest_path, self.IAM_ROLE
        )

    @logger
    def load_spark_table_into_redshift(
        self,
        metastore_service,
        source_table_name,
        target_schema,
        target_table_name,
        overwrite,
    ):
        """
        Load the data from a table created on spark metastore to a table in Redshift

        :param metastore_service: MetastoreService object
        :param source_table_name: name of the table in spark metastore without db prefix
        :param target_schema: name of the target schema in redshift
        :param target_table_name: name of the target table in redshift without schema prefix
        :param overwrite: boolean parameter to decide if the method should perform a delete on
                          the table before load the data
        :return: None
        """
        now = datetime.now()
        year, month, day = now.year, now.month, now.day

        # create manifest file
        files = metastore_service.get_file_paths_from_table(
            self.s3_service, source_table_name
        )
        manifest_dict = self._create_manifest_dict(files)
        manifest_json = json.dumps(manifest_dict)
        manifest_path = self.MANIFEST_PATH_TEMPLATE.format(
            self.dw_bucket, target_schema, target_table_name, year, month, day
        )
        self.s3_service.upload_file(manifest_json, manifest_path)

        # copy command
        command = self._create_copy_command(
            target_schema, target_table_name, manifest_path
        )
        if overwrite:
            self.redshift_client.run_command(
                "DROP TABLE IF EXISTS {}.{}".format(target_schema, target_table_name)
            )
        self.redshift_client.run_command(command)
