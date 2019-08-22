import time

import boto3
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("AthenaClient")


class AthenaClient:
    """
    This a temporary client for Athena. In the future we are going to use an AWS
    client existing in its own repository.
    """

    QUERY_OUTPUT_PATH = "s3://5a-datalake/temp/databricks_output/"

    @staticmethod
    def get_athena_client():
        return boto3.client("athena", "us-east-1")

    @staticmethod
    def start_athena_query(query, database):
        client = AthenaClient.get_athena_client()
        response = client.start_query_execution(
            QueryString=query,
            QueryExecutionContext={"Database": database},
            ResultConfiguration={"OutputLocation": AthenaClient.QUERY_OUTPUT_PATH},
        )
        return response

    @staticmethod
    @logger
    def execute_athena_query(query, database):
        execution = AthenaClient.start_athena_query(query, database)
        execution_id = execution["QueryExecutionId"]
        state = "RUNNING"
        client = AthenaClient.get_athena_client()
        while state in ["RUNNING"]:
            response = client.get_query_execution(QueryExecutionId=execution_id)
            if (
                "QueryExecution" in response
                and "Status" in response["QueryExecution"]
                and "State" in response["QueryExecution"]["Status"]
            ):
                state = response["QueryExecution"]["Status"]["State"]
                if state == "FAILED":
                    error_msg = response["QueryExecution"]["Status"][
                        "StateChangeReason"
                    ]
                    raise RuntimeError(
                        "m=execute_athena_query, msg=Athena client failed when "
                        "executing the query., query={}, error={}".format(
                            query, error_msg
                        )
                    )
                elif state == "SUCCEEDED":
                    return execution_id
            time.sleep(3)

    @staticmethod
    @logger
    def add_partition(database, table_name, partition_by_dict):
        add_partition_query = "ALTER TABLE {}.{} ADD IF NOT EXISTS PARTITION ({});"
        partitions_section = ", ".join(
            [
                "{} = {}".format(k, v)
                if not isinstance(v, str)
                else "{} = '{}'".format(k, v)
                for k, v in partition_by_dict.items()
            ]
        )
        add_partition_query = add_partition_query.format(
            database, table_name, partitions_section
        )
        AthenaClient.execute_athena_query(add_partition_query, database)

    @staticmethod
    @logger
    def repair_table_partitions(database, table_name):
        AthenaClient.execute_athena_query(
            "MSCK REPAIR TABLE `{}`.`{}`;".format(database, table_name), database
        )

    @staticmethod
    @logger
    def overwrite_external_table(
        database, table_name, s3_table_path, table_schema, partition_by, base_format
    ):
        drop_query = "DROP TABLE IF EXISTS {}.{}".format(database, table_name)
        AthenaClient.execute_athena_query(drop_query, database)
        logger.info(
            "m=overwrite_external_table, table={}.{}, msg=Dropped table in Athena successfully".format(
                database, table_name
            )
        )

        AthenaClient.create_external_table(
            database, table_name, s3_table_path, table_schema, partition_by, base_format
        )

    @staticmethod
    @logger
    def create_external_table(
        database, table_name, s3_table_path, table_schema, partition_by, base_format
    ):
        create_query = """
            CREATE EXTERNAL TABLE
            `{database}`.`{table}`
            (
              {columns}
            )
            {partitioned_by}
            {format}
            LOCATION '{path}'
            {properties}
            ;"""

        columns_section = ",\n  ".join(
            [
                "`" + col + "` " + col_type.upper()
                for col, col_type in table_schema.items()
                if not partition_by or col not in partition_by
            ]
        )

        partitions_section = ""
        if partition_by:
            partitions_section = "PARTITIONED BY (\n  {}\n)".format(
                ",\n  ".join(
                    ["`" + col + "` " + table_schema[col] for col in partition_by]
                )
            )

        create_query = create_query.format(
            database=database,
            table=table_name,
            columns=columns_section,
            partitioned_by=partitions_section,
            format=base_format["format"],
            path=s3_table_path,
            properties=base_format["properties"],
        )

        AthenaClient.execute_athena_query(create_query, database)
        logger.info(
            "m=create_external_table, table={}.{}, msg=The table was created successfully in Athena".format(
                database, table_name
            )
        )
