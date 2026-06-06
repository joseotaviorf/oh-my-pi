from argparse import ArgumentParser

import joblib
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_lost_listings_enrich"

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("context")
    parser.add_argument("execution_date")

    add_validation_target_args(parser)
    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context
    execution_date = args.execution_date

    config_service = ConfigurationService(f"enrich_{source}")
    table_name = config_service.get_config("table_name")
    enrich_partition_cols = config_service.get_config("enrich_partition_cols")
    amenities_query = config_service.get_config("amenities_query")
    segements_mapping = config_service.get_config("segements_mapping")
    lost_listings_query = config_service.get_config("lost_listings_query")
    lost_listings_model_path = config_service.get_config("lost_listings_model_path")

    logger.info(
        f"""m=__main__, environment={env}, source={source}, context={context},
        datalake_bucket={datalake_bucket}, execution_date={execution_date},
        msg=Starting Spark job..."""
    )

    spark_client = SparkClient()

    dim_house_listing_amenities = spark_client.conn.sql(amenities_query)
    dim_house_listing_amenities.createOrReplaceTempView("dim_house_listing_amenities")

    model = joblib.load(lost_listings_model_path)

    lost_listings_df_pd = spark_client.conn.sql(
        lost_listings_query.format(execution_date=execution_date)
    ).toPandas()
    lost_listings_df_pd["cluster"] = model.predict(lost_listings_df_pd.iloc[:, 1:-3])
    lost_listings_df_pd["cluster"] = lost_listings_df_pd["cluster"].map(
        segements_mapping
    )

    df = spark_client.create_dataframe(lost_listings_df_pd)

    db_info = DatalakeMetastoreService.get_db_info(env, context, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(write_database_name)

    delta_loader = DeltaLoader()

    s3_path = f"{write_location}{write_table_name}"
    full_table_name = f"{write_database_name}.{write_table_name}"

    logger.info(f"Table {full_table_name} will be loaded as Delta.")

    delta_loader.load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=df,
        partition_by=enrich_partition_cols,
    )

    spark_metastore_service.refresh_table(write_database_name, write_table_name)
