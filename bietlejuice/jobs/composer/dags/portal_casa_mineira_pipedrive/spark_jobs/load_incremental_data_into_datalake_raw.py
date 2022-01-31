import json
import logging
from argparse import ArgumentParser
from pyspark.sql.types import StructField
from pyspark.sql.types import StructType
from pyspark.sql.types import StringType
from pyspark.sql.functions import unix_timestamp, to_timestamp, to_date

from quintoandar_logger import QuintoAndarLogger
from quintoandar_pipedrive_api_client.clients import PipedriveClient
from quintoandar_pipedrive_api_client.consumers import PipedrivePagedConsumer
from quintoandar_pipedrive_api_client.consumers.pipedrive_parallel_consumer import (
    PipedriveParallelConsumer,
)
from quintoandar_pipedrive_api_client.constants.endpoint_enum import EndpointEnum

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_credentials():
    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=APIEnum.PIPEDRIVE
    )
    return json.loads(json_credentials)


def get_all_deals(client):
    endpoint_enum = EndpointEnum.PIPEDRIVE_GET_ALL_DEALS.value
    all_deals = PipedrivePagedConsumer(endpoint_enum=endpoint_enum, client=client)
    all_deals = all_deals.sync()
    return all_deals["data"]


def get_all_stages(client):
    endpoint_enum = EndpointEnum.PIPEDRIVE_GET_ALL_STAGES.value
    all_stages = PipedrivePagedConsumer(endpoint_enum=endpoint_enum, client=client)
    all_stages = all_stages.sync()
    return all_stages["data"]


def get_deals_flow(client, deals_id):
    endpoint_enum = EndpointEnum.PIPEDRIVE_GET_DEAL_FLOW.value
    consumer = PipedriveParallelConsumer(endpoint_enum=endpoint_enum, client=client)
    response = consumer.sync(
        ids_list=deals_id, extra_params={"api_token": client.api_token}
    )

    all_stages = []
    for deal_flow in response:
        for stage in deal_flow:
            all_stages.append(stage)

    return all_stages


def get_deals_fields(client):
    endpoint_enum = EndpointEnum.PIPEDRIVE_GET_DEAL_FIELDS.value
    deal_fields = PipedrivePagedConsumer(endpoint_enum=endpoint_enum, client=client)
    deal_fields = deal_fields.sync()
    return deal_fields["data"]


def is_a_hash_key(key):
    return len(key) == 40


def replace_hash_keys_to_field_name(deals, fields):

    columns_renamed = {
        "tipo_de_plano": "plano",
        "nº_imóveis_informados_pelo_cliente": "imoveis_informados",
        "nº_imóveis_no_xml": "xml_imoveis",
        "nº_imóveis_publicados": "imoveis_pub",
        "consultor_que_fez_a_ligação": "consultor_que_fez_a_ligacao",
        "nº_imóveis": "numero_imoveis",
        "nº_imóveis_(extenso)": "numero_imoveis_extenso",
        "sistema_de_integração": "sistema_de_integracao",
        "status_de_publicação": "status_de_publicacao",
        "dia_de_cobrança": "dia_de_cobranca",
        "bonificação": "bonificacao",
        "data_da_ligação": "data_da_ligacao",
        "início_da_cobrança": "inicio_da_cobranca",
        "envio_de_e-mail_de_boas_vindas": "envio_de_email_de_boas_vindas",
        "cidade_imobiliária": "cidade",
        "estado_imobiliária": "estado",
    }

    for field in fields:
        for deal in deals:
            if is_a_hash_key(field["key"]) and field["key"] in deal:
                new_key_name = field["name"].replace(" ", "_").lower()

                if new_key_name in columns_renamed:
                    deal[columns_renamed[new_key_name]] = deal[field["key"]]
                else:
                    deal[new_key_name] = deal[field["key"]]

                del deal[field["key"]]

    return deals


def filter_deals(df):
    return df.filter("update_time >= '2021-01-01'").filter(
        "pipeline_id == 6 or pipeline_id == 8 or pipeline_id == 9"
    )


def filter_deal_flow(deals_flow):
    select_items = []
    item = deals_flow

    if item["object"] == "dealChange":

        if item["data"]["field_key"] == "stage_id":

            data = item["data"]
            try:
                old_value = data["additional_data"]["old_value_formatted"]
                new_value = data["additional_data"]["new_value_formatted"]
            except Exception:
                old_value, new_value = 0, 0

            result = {
                "id": data["id"],
                "log_time": data["log_time"],
                "id_deal": data["item_id"],
                "old_stage": old_value,
                "new_stage": new_value,
                "field_key": data["field_key"],
            }
            select_items.append(result)

        elif item["data"]["field_key"] == "add_time":
            data = item["data"]
            result = {
                "id": data["id"],
                "log_time": data["log_time"],
                "id_deal": data["item_id"],
                "old_stage": "Inexistente",
                "new_stage": "Lead",
                "field_key": data["field_key"],
            }
            select_items.append(result)

        elif item["data"]["field_key"] == "status":
            data = item["data"]
            if data["new_value"] == "won":
                result = {
                    "id": data["id"],
                    "log_time": data["log_time"],
                    "id_deal": data["item_id"],
                    "old_stage": data["old_value"],
                    "new_stage": data["new_value"],
                    "field_key": data["field_key"],
                }
                select_items.append(result)

    return select_items


def generate_schema(data):
    if len(data):
        columns = data[0].keys()
        type_array = [StructField(column_name, StringType()) for column_name in columns]
        schema = StructType(type_array)
        return schema


def filter_by_execution_date(df, filter_date, table_name):
    if table_name == "deals":
        logic_filter = "close_time >= '{filter_date}' or update_time >= '{filter_date}' or add_time >= '{filter_date}'"

    elif table_name == "deals_flow":
        logic_filter = "log_time >= '{filter_date}'"

    return df.filter(logic_filter.format(filter_date=filter_date))


def select_deals_flow(all_deals_flow):
    selected_deals_flow = []

    for flow in all_deals_flow:
        selected_deal_flow = filter_deal_flow(flow)
        for item in selected_deal_flow:
            selected_deals_flow.append(item)

    return selected_deals_flow


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("context", help="name of the context")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument(
        "full_load_execution_date", help="full load execution date date in str format"
    )

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context
    execution_date = args.execution_date
    full_load_execution_date = args.full_load_execution_date

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, 
            source={source}, context={context}, execution_date={execution_date}, 
            full_load={full_load_execution_date}, msg=print spark jobs args"
        """
    )

    if full_load_execution_date:
        execution_date = full_load_execution_date

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials = get_credentials()
    client = PipedriveClient(api_token=credentials["api_token"], attempts=15)

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, 
            source={source}, context={context}, msg=API Client created!"
        """
    )

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    config_service = ConfigurationService(context)
    partition_cols = config_service.get_config("partition_cols")

    deals = get_all_deals(client)
    fields = get_deals_fields(client)
    deals_normalized = replace_hash_keys_to_field_name(deals, fields)
    total_deals_normilize = len(deals_normalized)

    date_time_format = "yyyy-MM-dd HH:mm:ss"

    schema = generate_schema(deals_normalized)
    deals_df = spark_client.create_dataframe(data=deals_normalized, schema=schema)
    deals_df = deals_df.withColumn(
        "update_time",
        to_date(to_timestamp(unix_timestamp("update_time", date_time_format))),
    )
    deals_df = filter_deals(deals_df)
    deals_df = filter_by_execution_date(deals_df, execution_date, "deals")
    deals_ids = deals_df.select("id").rdd.map(lambda row: row[0]).collect()

    total_deals = deals_df.count()
    deals_flow_total = 0
    stages_total = 0

    for table_name, table_config in config_service.get_config(
        "tables_configurations"
    ).items():

        column_create_date = table_config["column_create_date"]

        if deals_normalized and total_deals > 0:

            if table_name == "deals":
                df = deals_df

            elif table_name == "deals_flow":
                all_deals_flow = get_deals_flow(client, deals_ids)
                selected_deals_flow = select_deals_flow(all_deals_flow)

                deals_flow_schema = generate_schema(selected_deals_flow)
                df = spark_client.create_dataframe(
                    data=selected_deals_flow, schema=deals_flow_schema
                )
                df = df.withColumn(
                    column_create_date,
                    to_date(
                        to_timestamp(
                            unix_timestamp(column_create_date, date_time_format)
                        )
                    ),
                )
                df = filter_by_execution_date(df, execution_date, "deals_flow")
                deals_flow_total = df.count()

            elif table_name == "stages":
                all_stages = get_all_stages(client)
                all_stages_schema = generate_schema(all_stages)
                df = spark_client.create_dataframe(
                    data=all_stages, schema=all_stages_schema
                )
                df = df.withColumn(
                    column_create_date,
                    to_date(
                        to_timestamp(
                            unix_timestamp(column_create_date, date_time_format)
                        )
                    ),
                )
                stages_total = df.count()

            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column(column_create_date)
                .output()
            )

            # loaders
            s3_loader.load_incremental_table(
                df=df,
                database_name=database_name,
                table_name=table_name,
                database_location=database_location,
                format_options=format_options,
                partition_cols=partition_cols,
            )
            spark_metastore_loader.update_metastore(
                df,
                database_name,
                table_name,
                format_options,
                database_location,
                partition_cols,
                force_recreate=False,
            )
            spark_metastore_service.create_new_partitions_from_df(
                database_name=database_name,
                table_name=table_name,
                df=df,
                partition_cols=partition_cols,
            )
        else:
            logger.warning(
                f"""m=__main__, table_name={table_name},
                msg=No data returned from API."""
            )

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, 
            source={source}, context={context}, msg=Total of deals is " {total_deals_normilize}
        """
    )

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, 
            source={source}, context={context}, msg=Total of deals is " {total_deals}
        """
    )

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, 
            source={source}, context={context}, msg=Total of deals flow is " {deals_flow_total}
        """
    )

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, 
            source={source}, context={context}, msg=Total of stages is " {stages_total}
        """
    )
