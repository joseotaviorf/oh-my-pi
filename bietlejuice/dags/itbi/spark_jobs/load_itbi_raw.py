import logging
import requests
import re
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from pyspark import SparkFiles
from pyspark.sql.types import DecimalType
from pyspark.sql.functions import lpad, lit

from bietlejuice.pipeline import IncrementalTableLoaderPipeline, FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

from dateutil.relativedelta import relativedelta
from datetime import datetime
from datetime import date


JOB_NAME = "load_itbi_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(
    session_params={
        "spark.jars.packages": "com.crealytics:spark-excel_2.12:3.1.2_0.17.1"
    }
)


def main():
    environment, datalake_bucket, source, execution_date, full_load_execution_date = (
        parse_arguments()
    )
    logger.info(
        f"""
        m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
         execution_date={execution_date}, full_load_execution_date={full_load_execution_date}
         msg=Starting Spark job...
        """
    )

    if full_load_execution_date:
        execution_date = full_load_execution_date

    config_service = ConfigurationService(source)

    for key, value in config_service.get_config("tables").items():

        table_name = key
        source_url = value["source"]["site_url"]
        source_download_page_url = value["source"]["site_download_page_url"]
        source_file_pattern = value["source"]["file_pattern"]
        source_format = value["source"]["format"]
        source_read_format = value["source"]["spark_read_format"]
        is_incremental = value["is_incremental"]
        columns_raname_mapped = value["columns_to_raname"].items()

        logger.info(
            f"""
            m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
            msg=Configuration table, table_name={table_name}, source_url={source_url}, source_format={source_format}, is_incremental={is_incremental}
            """
        )

        dataframe = get_data(
            source_url,
            source_download_page_url,
            source_format,
            source_file_pattern,
            source_read_format,
            execution_date,
        )

        if dataframe:
            logger.info(
                f"""
                m=main, environment={environment}, datalake_bucket={datalake_bucket}, source={source}, execution_date={execution_date}
                msg=Dataframe Size {dataframe.count()}
                """
            )

            if columns_raname_mapped:
                dataframe = rename_columns(dataframe, columns_raname_mapped)

            dataframe = format_columns(dataframe)

            load_dataframe_into_datalake(
                dataframe,
                table_name,
                is_incremental,
                environment,
                source,
                datalake_bucket,
            )


def get_data(
    source_url,
    source_download_page_url,
    source_format,
    source_file_pattern,
    source_read_format,
    execution_date,
):

    YEAR, MONTH = get_year_month_to_execute(execution_date)

    try:
        urls = scrap_files_url(
            source_download_page_url, source_file_pattern, source_format
        )
        data_path = source_url + list(filter(lambda s: YEAR in s, urls))[0]
        file_name = data_path.split("/")[-1]

        logger.info(
            f"""
            msg=DataPath {data_path}, FileName {file_name}
        """
        )

        spark_client.conn.sparkContext.addFile(data_path)

        df = (
            spark_client.conn.read.format(source_read_format)
            .option("dataAddress", f"'{MONTH}-{YEAR}'!")
            .option("header", "true")
            .option("inferSchema", "true")
            .load("file://" + SparkFiles.get(file_name))
        )

        df = df.withColumn("source_file", lit(data_path))
        df = df.withColumn("source_tab", lit(f"{MONTH}-{YEAR}"))
        df = df.withColumn("dt_load", lit(date.today()))

        logger.info(
            f"""
            msg=Success on get data from {data_path}
        """
        )

        return df

    except Exception as e:
        logger.warning(
            f"""
            msg=Fail on get data from {source_url} , error={e}
        """
        )

        return None


def scrap_files_url(source_url, source_file_pattern, source_format):
    u = requests.get(source_url)
    urls = re.findall(f"""{source_file_pattern}.+?.{source_format}""", u.text)
    return urls


def rename_columns(dataframe, columns_rename_mapped):

    for old_name, new_name in columns_rename_mapped:
        dataframe = dataframe.withColumnRenamed(old_name, new_name)

    return dataframe


def format_columns(dataframe):

    dataframe = dataframe.withColumn("cep", lpad(dataframe.cep, 8, "0"))
    dataframe = dataframe.withColumn(
        "valor_transacao_declarado",
        dataframe.valor_transacao_declarado.cast(DecimalType(18, 2)),
    )
    dataframe = dataframe.withColumn(
        "valor_venal_referencia",
        dataframe.valor_venal_referencia.cast(DecimalType(18, 2)),
    )
    dataframe = dataframe.withColumn(
        "valor_venal_referencia_proporcional",
        dataframe.valor_venal_referencia_proporcional.cast(DecimalType(18, 2)),
    )
    dataframe = dataframe.withColumn(
        "valor_financiado", dataframe.valor_financiado.cast(DecimalType(18, 2))
    )

    return dataframe


def get_year_month_to_execute(execution_date):
    """ This function will return the year and month of the last month"""

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")
    date_in_last_month = execution_date - relativedelta(months=1)

    month = transform_month_to_portuguese_relative(date_in_last_month.month)
    year = str(date_in_last_month.year)

    return year, month


def transform_month_to_portuguese_relative(month):

    months = {
        "1": "JAN",
        "2": "FEV",
        "3": "MAR",
        "4": "ABR",
        "5": "MAI",
        "6": "JUN",
        "7": "JUL",
        "8": "AGO",
        "9": "SET",
        "10": "OUT",
        "11": "NOV",
        "12": "DEZ",
    }

    return months[str(month)]


def create_date_partitions(df):
    """Creates the columns year, month and day using updated_at"""

    return (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("dt_load")
        .output()
    )


def load_dataframe_into_datalake(
    df, table_name, is_incremental, environment, source, datalake_bucket
):
    """Loads the dataframes into S3, either incrementally or fully, depending on the config."""

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    partition_cols = ["year", "month", "day"]

    if df.rdd.isEmpty():
        logger.info(f"m=__main__, msg={table_name}'s RDD is empty")

    if is_incremental:
        df = create_date_partitions(df)

        IncrementalTableLoaderPipeline(
            database_name,
            table_name,
            database_location,
            LayerEnum.RAW,
            None,
            partition_cols,
        ).load_and_register(df, format_options)
    else:
        FullTableLoaderPipeline(
            database_name, table_name, database_location, LayerEnum.RAW, None
        ).load_and_register(df, format_options)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("execution_date")
    parser.add_argument("full_load_execution_date")

    args = parser.parse_args()

    return (
        args.env,
        args.datalake_bucket,
        args.source,
        args.execution_date,
        args.full_load_execution_date,
    )


if __name__ == "__main__":
    main()
