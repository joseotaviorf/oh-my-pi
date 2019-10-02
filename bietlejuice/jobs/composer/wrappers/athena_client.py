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

    def __init__(self):
        self.client = boto3.client("athena", "us-east-1")

    def start_athena_query(self, query, database):
        response = self.client.start_query_execution(
            QueryString=query,
            QueryExecutionContext={"Database": database},
            ResultConfiguration={"OutputLocation": self.QUERY_OUTPUT_PATH},
        )
        return response

    @logger
    def execute_athena_query(self, query, database):
        execution = self.start_athena_query(query, database)
        execution_id = execution["QueryExecutionId"]
        state = "RUNNING"
        while state in ["RUNNING"]:
            response = self.client.get_query_execution(QueryExecutionId=execution_id)
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

    @logger
    def add_partition(self, database, table_name, partition_by_dict):
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
        self.execute_athena_query(add_partition_query, database)

    @logger
    def repair_table_partitions(self, database, table_name):
        self.execute_athena_query(
            "MSCK REPAIR TABLE `{}`.`{}`;".format(database, table_name), database
        )

    @logger
    def overwrite_external_table(
        self,
        database,
        table_name,
        s3_table_path,
        table_schema,
        partition_by,
        base_format,
    ):
        drop_query = "DROP TABLE IF EXISTS {}.{}".format(database, table_name)
        self.execute_athena_query(drop_query, database)
        logger.info(
            "m=overwrite_external_table, table={}.{}, msg=Dropped table in Athena successfully".format(
                database, table_name
            )
        )

        self.create_external_table(
            database, table_name, s3_table_path, table_schema, partition_by, base_format
        )

    @logger
    def create_database(self, database):
        create_query = "CREATE DATABASE IF NOT EXISTS {};".format(database)
        self.execute_athena_query(create_query, database)
        logger.info(
            "m=create_database, database={}, msg=The schema was created successfully in Athena".format(
                database
            )
        )

    @logger
    def create_external_table(
        self,
        database,
        table_name,
        s3_table_path,
        table_schema,
        partition_by,
        base_format,
    ):

        """
            Create automatic ddl for Athena tables. Params descriptions:

            database: database from Athena table,
            table_name: table name for the Athena table created,
            s3_table_path: files location for Athena table created
            table_schema: dict with spark table schema
            partition_by: list with columns to partition the table
            base_format: dict with file format and optional [serde/tbl] properties keys.
        """

        create_query = (
            "\nCREATE EXTERNAL TABLE IF NOT EXISTS `{database}`.`{table}`("
            "\n{columns}"
            "\n) {partitioned_by}"
            "\n{format}"
            "{serdeproperties}"
            "\nLOCATION '{path}'"
            "{tblproperties};"
        )

        # columns builder
        columns_section = ",\n".join(
            [
                "  `" + col + "` " + col_type
                for col, col_type in table_schema.items()
                if not partition_by or col not in partition_by
            ]
        )

        # partitions builder
        partitions_section = ""
        if partition_by:
            partitions_section = "\nPARTITIONED BY (\n  {}\n)".format(
                ",\n  ".join(
                    [" `" + col + "` " + table_schema[col] for col in partition_by]
                )
            )

        create_query = create_query.format(
            database=database,
            table=table_name,
            columns=columns_section,
            partitioned_by=partitions_section,
            format=base_format["format"],
            path=s3_table_path,
            serdeproperties=""
            if "serdeproperties" not in base_format.keys()
            else "\n" + base_format["serdeproperties"],
            tblproperties=""
            if "tblproperties" not in base_format.keys()
            else "\n" + base_format["tblproperties"],
        )

        # create database if not exists
        self.create_database(database)

        # create table
        self.execute_athena_query(create_query, database)
        logger.info(
            "m=create_external_table, table={}.{}, msg=The table was created successfully in Athena".format(
                database, table_name
            )
        )
