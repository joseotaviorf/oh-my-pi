import pickle
from datetime import datetime
import pandas as pd

from quintoandar_logger import QuintoAndarLogger
from argparse import ArgumentParser

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService


JOB_NAME = "load_nps_reversion_landlord_enrich"
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
    output_table_name = config_service.get_config("offboarding_landlord_output_table_name")
    input_table_name = config_service.get_config("offboarding_landlord_input_table_name")
    partition_cols = config_service.get_config("output_partitions")
    model_filename = config_service.get_config("offboarding_landlord_model_filename")
    input_query = config_service.get_config("offboarding_input_query")
    input_query_columns = config_service.get_config("offboarding_landlord_input_columns")
    model_output_column = config_service.get_config("model_output_column")
    model_predicted_date_column = config_service.get_config("model_predicted_date_column")
    offboarding_landlord_output_columns = config_service.get_config("offboarding_landlord_output_columns")

    logger.info(
        f"""m=__main__, environment={env}, source={source}, context={context},
        datalake_bucket={datalake_bucket}, execution_date={execution_date},
        msg=Starting Spark job..."""
    )

    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(env, context, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    rf = pickle.load(open(model_filename, "rb"))

    input_query = input_query.format(table_name=input_table_name, execution_date=execution_date)
    df_predict = spark_client.conn.sql(input_query).toPandas()

    df_predict[model_output_column] = rf.predict_proba(df_predict[input_query_columns])[:,1]
    df_predict[model_predicted_date_column] = datetime.strptime(execution_date, "%Y-%m-%d").date()
    df_predict = df_predict[offboarding_landlord_output_columns]
    df = spark_client.create_dataframe(df_predict)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=df,
        format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
        s3_path=f"{database_location}{output_table_name}",
        partitions=partition_cols,
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=output_table_name,
        format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
        database_location=database_location,
        partitions=partition_cols,
        force_recreate=False,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=output_table_name,
        partition_cols=partition_cols,
    )
