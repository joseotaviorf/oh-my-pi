from datetime import datetime
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit

JOB_NAME = "load_management_hierarchy_enrich"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("context")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context
    execution_date = args.execution_date

    config_service = ConfigurationService(f"enrich_{source}")
    table_name = "management_hierarchy"

    managers_query = """
        SELECT
            id_period_of_service,
            id_manager_period_of_service,
            id_assignment,
            id_manager_assignment
        FROM
            datalake_pin.managers_history
        WHERE
            dt_effective_started <= CURRENT_DATE
            AND id_manager_assignment <> '300000008488092'
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY assignment_number ORDER BY dt_effective_started DESC) = 1
    """

    logger.info(
        f"""m=__main__, environment={env}, source={source}, context={context},
        datalake_bucket={datalake_bucket}, execution_date={execution_date},
        msg=Starting Spark job..."""
    )

    spark_client = SparkClient()

    df = spark_client.conn.sql(managers_query)
    df = df.filter(df.id_manager_assignment.isNotNull())

    df_degree = df.withColumn("separation_degree", lit(1))\
                  .withColumn("is_direct_manager", lit(True))\
                  .select("id_assignment", "id_manager_assignment", "separation_degree", "is_direct_manager", "id_period_of_service", "id_manager_period_of_service")

    df_result = df_degree

    max_iterations = 10

    for i in range(2, max_iterations + 1):
        df_next_degree = df.alias("df1")\
            .join(df_degree.alias("df2"), col("df1.id_manager_assignment") == col("df2.id_assignment"))\
            .select(
                col("df1.id_assignment"),
                col("df2.id_manager_assignment"),
                lit(i).alias("separation_degree"),
                lit(False).alias("is_direct_manager"),
                col("df1.id_period_of_service"),
                col("df2.id_manager_period_of_service")
            )

        df_result = df_result.union(df_next_degree)
        df_degree = df_next_degree

    df_separation = df_result.orderBy("id_assignment", "separation_degree")

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    delta_loader = DeltaLoader()

    s3_path = database_location + table_name
    full_table_name = f"{database_name}.{table_name}"

    logger.info(
        f"Table {full_table_name} will be loaded as Delta."
    )

    delta_loader.load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=df_separation,
    )

    spark_metastore_service.refresh_table(
        database_name, table_name
    )
