import json
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("RedshiftLoader")


class RedshiftLoader:
    """
    Loads data into Redshift.

    :param redshift_client: a client to handle the connection with Redshift
    :type redshift_client: PostgresClient
    :param s3_service: a service to interact with S3
    :type s3_service: S3Service
    :param dw_bucket: S3 bucket containing the analytical tables
    :type dw_bucket: str
    """

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

    def __init__(self, spectrum_iam_role, redshift_client, s3_service, dw_bucket):
        self.spectrum_iam_role = spectrum_iam_role
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
            schema, table, manifest_path, self.spectrum_iam_role
        )

    @logger
    def load_table_from_metastore(
        self,
        metastore_service,
        source_schema,
        source_table_name,
        target_schema,
        target_table_name,
        overwrite,
    ):
        """
        Loads the data from a table on a Metastore into a table in Redshift.

        :param metastore_service: a metastore service
        :type metastore_service: MetastoreService
        :param source_schema: name of the source schema in the metastore
        type source_schema: str
        :param source_table_name: name of the table in the metastore without db prefix
        :type source_table_name: str
        :param target_schema: name of the target schema in redshift
        :type target_schema: str
        :param target_table_name: name of the target table in Redshift without schema
        prefix
        :type: target_table_name: str
        :param overwrite: option to perform a delete on the table before loading the
        data
        :type overwrite: bool
        :return: None
        """
        now = datetime.now()
        year, month, day = now.year, now.month, now.day

        # create manifest file
        files = metastore_service.get_file_paths_and_sizes_from_table(
            source_schema, source_table_name, self.s3_service
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
            self.redshift_client.run(
                "DELETE FROM {}.{}".format(target_schema, target_table_name)
            )
        self.redshift_client.run(command)
