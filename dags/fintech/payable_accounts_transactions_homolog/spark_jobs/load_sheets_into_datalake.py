import ast
from datetime import datetime, timedelta
from functools import reduce
import logging
import json
import io

from argparse import ArgumentParser
import operator

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.formatters import StringFormatter
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql import functions, DataFrame
from pyspark.sql.types import StructField, StructType, StringType
import pandas as pd
from googleapiclient.discovery import build
from oauth2client.service_account import ServiceAccountCredentials
from googleapiclient.http import MediaIoBaseDownload, HttpError

JOB_NAME = "load_sheets_into_datalake"
TEMPORARY_DRIVE_FOLDER_ID = "1J_V6VFE0bVO7iMhxVc8rzg4E-oHhc-D_"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __convert_excel_numeric_date(excel_date):
    if excel_date is not None and excel_date.isnumeric():
        numeric_date = int(excel_date)
        if numeric_date >= 60:
            numeric_date -= 1
        return str(
            (datetime(1899, 12, 31) + timedelta(days=numeric_date)).replace(
                microsecond=0
            )
        )
    else:
        return excel_date


def __columns_to_alphanumeric_snake_case(df):
    """
    This method applies changes to dataframe column names.
    @param df: dataframe with google sheets data.
    @return: dataframe
    """
    old_columns = df.columns
    new_columns = [
        StringFormatter.set_alphanumeric_snake_case(column) for column in old_columns
    ]
    return df.toDF(*new_columns)


def __generate_schema(dataframe):
    """
    This method creates the schema from the data returned by the API.
    @param data: list with data returned by the API.
    @return: StructType
    """
    return StructType(
        [StructField(column_name, StringType()) for column_name in dataframe.columns]
    )


def __get_auth(dbutils):
    """
    This method gets credentials for the sheets API.
    @param dbutils: DBUtils.
    @return: dict and str
    """
    credentials = json.loads(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.GSHEETS_CREDENTIALS)
    )
    scope = credentials.pop("scope")

    return credentials, scope


def __get_gdrive_credentials(credentials):
    """
    This method gets credentials instance for the sheets API.
    @param credentials: dict.
    @return: ServiceAccountCredentials
    """
    SCOPES = ["https://www.googleapis.com/auth/drive"]

    return ServiceAccountCredentials.from_json_keyfile_dict(credentials, SCOPES)


def __list_files_gdrive(client, query):
    """
    This method list files from Gdrive API.
    @param client: googleapiclient.discovery.Resource.
    @param query: str.
    @return: list
    """

    files = []
    page_token = None
    while True:
        results = (
            client.files()
            .list(
                pageSize=100,
                pageToken=page_token,
                fields="nextPageToken, files(id, name, mimeType)",
                q=query,
                includeItemsFromAllDrives=True,
                supportsAllDrives=True,
            )
            .execute()
        )

        files.extend(results.get("files", []))
        page_token = results.get("nextPageToken")
        if not page_token:
            break
    return files


def __download_drive_file_as_bytes(drive_client, file_id, acknowledge_abuse=False):

    request = drive_client.files().get_media(
        fileId=file_id, acknowledgeAbuse=acknowledge_abuse
    )
    fh = io.BytesIO()
    downloader = MediaIoBaseDownload(fh, request)
    done = False
    try:
        while done is False:
            status, done = downloader.next_chunk()
        fh.seek(0)
    except HttpError as e:
        if (
            e.reason
            == "This file has been identified as malware or spam and cannot be downloaded."
        ):
            return __download_drive_file_as_bytes(
                drive_client, file_id, acknowledge_abuse=True
            )
    return fh


def __get_drive_file_ownership(drive_client, file_id):
    file_propeties = {"parents": [TEMPORARY_DRIVE_FOLDER_ID]}
    request = (
        drive_client.files()
        .copy(fileId=file_id, body=file_propeties, supportsAllDrives=True)
        .execute()
    )
    return request["id"]


def __delete_drive_file(drive_client, file_id):
    drive_client.files().delete(fileId=file_id).execute()
    return True


def __drive_file_download(drive_client, file_id):
    new_id = __get_drive_file_ownership(drive_client, file_id)
    file = __download_drive_file_as_bytes(drive_client, new_id)
    __delete_drive_file(drive_client, new_id)
    return file


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name", help="table name to insert into datalake")
    parser.add_argument(
        "root_folder_id",
        help="sheets sheet name, sheet id, and (optional) preload time in seconds",
    )
    parser.add_argument(
        "columns_to_read",
        help="List of columns names in the sheet files that will be retrieved",
    )

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    root_folder_id = args.root_folder_id
    columns_to_read = ast.literal_eval(args.columns_to_read)

    logger.info(
        f"""
                m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
                table_name={table_name}, root_folder_id={root_folder_id}, columns_to_read={columns_to_read}
                execution_date=execution_date msg=Starting spark job...
        """
    )

    # Initializing GoogleDrive Client
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils)

    gdrive_client = build(
        "drive", "v3", credentials=__get_gdrive_credentials(credentials)
    )

    # Initializing clients
    spark_client = SparkClient()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    spark_metastore_service = SparkMetastoreService(spark_client)
    database_name = datalake_info["db_raw_databricks"]
    spark_metastore_service.create_database(database_name)

    database_location = datalake_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")

    # Google Drive folder listing
    root_query = f"'{root_folder_id}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
    items = __list_files_gdrive(gdrive_client, root_query)
    cap_year_folders_ids = []
    for item in items:
        if any(
            str(year) in item["name"] for year in range(2021, datetime.now().year + 1)
        ):
            cap_year_folders_ids.append(item["id"])
    cap_year_folder_queries = [
        f"'{cap_year_folder_id}' in parents and trashed=false"
        for cap_year_folder_id in cap_year_folders_ids
    ]
    infos_sheets = [
        __list_files_gdrive(gdrive_client, cap_year_folder_query)
        for cap_year_folder_query in cap_year_folder_queries
    ]
    infos_sheets = reduce(operator.concat, infos_sheets)

    # Retrieve all sheets
    dfs = {"itau": [], "bradesco": [], "citi": []}
    dfs_2021 = {"itau": [], "bradesco": [], "citi": []}

    for i in infos_sheets:

        if "2021" in i["name"]:
            if (
                not i["name"].lower().endswith(".tmp")
                and "Controle Financeiro - CAP" in i["name"]
            ):
                engine = None if "xlsb" not in i["name"] else "pyxlsb"
                if "Terceiros" in i["name"]:
                    sheetname = str(2021)
                    usecols = columns_to_read + ["Itaú"] + ["Description"]
                    df_2021 = pd.read_excel(
                        __drive_file_download(gdrive_client, i["id"]),
                        dtype=str,
                        header=1,
                        sheet_name=sheetname,
                        usecols=usecols,
                        engine=engine,
                    )
                    df_2021 = spark_client.create_dataframe(df_2021, __generate_schema(df_2021))
                    dfs_2021["itau"].append(df_2021)
                else:
                    for sheetname in ["Bradesco", "Citi"]:
                        usecols = columns_to_read + [sheetname] + ["Description"]
                        df_2021 = pd.read_excel(
                            __drive_file_download(gdrive_client, i["id"]),
                            dtype=str,
                            header=1,
                            sheet_name=sheetname,
                            usecols=usecols,
                            engine=engine,
                        )
                        df_2021 = spark_client.create_dataframe(df_2021, __generate_schema(df_2021))
                        dfs_2021[sheetname.lower()].append(df_2021)
        else:
            if (
                not i["name"].lower().endswith(".tmp")
                and "Controle Financeiro - CAP" in i["name"]
            ):
                engine = None if "xlsb" not in i["name"] else "pyxlsb"
                if "Terceiros" in i["name"]:
                    sheetname = None
                    for year in range(2021, datetime.now().year + 1):
                        if str(year) in i["name"]:
                            sheetname = str(year)
                    usecols = columns_to_read + ["Itaú"]
                    df = pd.read_excel(
                        __drive_file_download(gdrive_client, i["id"]),
                        dtype=str,
                        header=1,
                        sheet_name=sheetname,
                        usecols=usecols,
                        engine=engine,
                    )
                    df = spark_client.create_dataframe(df, __generate_schema(df))
                    dfs["itau"].append(df)
                else:
                    for sheetname in ["Bradesco", "Citi"]:
                        usecols = columns_to_read + [sheetname]
                        df = pd.read_excel(
                            __drive_file_download(gdrive_client, i["id"]),
                            dtype=str,
                            header=1,
                            sheet_name=sheetname,
                            usecols=usecols,
                            engine=engine,
                        )
                        df = spark_client.create_dataframe(df, __generate_schema(df))
                        dfs[sheetname.lower()].append(df)


    # Create a pattern and union all sheets for not 2021 files
    df_itau = (
        reduce(DataFrame.unionAll, dfs["itau"])
        .drop("")
    )
    df_bradesco = (
        reduce(DataFrame.unionAll, dfs["bradesco"])
        .drop("")
    )
    df_citi = reduce(DataFrame.unionAll, dfs["citi"])

    df_itau = __columns_to_alphanumeric_snake_case(df_itau)
    df_bradesco = __columns_to_alphanumeric_snake_case(df_bradesco)
    df_citi = __columns_to_alphanumeric_snake_case(df_citi)

    df_itau = df_itau.withColumnRenamed("itau", "saldo_total")
    df_bradesco = df_bradesco.withColumnRenamed("bradesco", "saldo_total")
    df_citi = df_citi.withColumnRenamed("citi", "saldo_total")

    df = reduce(DataFrame.unionAll, [df_itau, df_bradesco, df_citi])

    # Create a pattern and union all sheets for 2021 files

    df_itau_2021 = (
        reduce(DataFrame.unionAll, dfs_2021["itau"])
        .drop("")
    )
    df_bradesco_2021 = (
        reduce(DataFrame.unionAll, dfs_2021["bradesco"])
        .drop("")
    )
    df_citi_2021 = reduce(DataFrame.unionAll, dfs_2021["citi"])

    df_itau_2021 = __columns_to_alphanumeric_snake_case(df_itau_2021)
    df_bradesco_2021 = __columns_to_alphanumeric_snake_case(df_bradesco_2021)
    df_citi_2021 = __columns_to_alphanumeric_snake_case(df_citi_2021)

    df_itau_2021 = df_itau_2021.withColumnRenamed("itau", "saldo_total")
    df_bradesco_2021 = df_bradesco_2021.withColumnRenamed("bradesco", "saldo_total")
    df_citi_2021 = df_citi_2021.withColumnRenamed("citi", "saldo_total")

    df_2021 = reduce(DataFrame.unionAll, [df_itau_2021, df_bradesco_2021, df_citi_2021])

    # Remove non-standard 'saldo inicial' rows and remove 'Description' only present in 2021 files and used for removing 'saldo inicial
    filter_all_columns = [
        functions.lower(functions.col(col)).contains("saldo inicial")
        for col in df_2021.columns
    ]
    df_2021 = df_2021.filter(~functions.greatest(*filter_all_columns)).drop("description")

    # Union 2021 and not 2021 files

    df = reduce(DataFrame.unionAll, [df, df_2021])

    # Fix ordinal excel dates
    convert_numeric_date_udf = functions.udf(__convert_excel_numeric_date, StringType())

    df = df.withColumn("pagamento", convert_numeric_date_udf(df.pagamento)).withColumn(
        "competencia", convert_numeric_date_udf(df.competencia)
    )

    # Add ts_load column

    df = df.withColumn("ts_load", functions.current_timestamp())

    # loaders
    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader.load_df(
        df=df, s3_path=f"{database_location}{table_name}", format_options=format_options
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )

    logger.info(
        f"""
            m={JOB_NAME}, table_name={table_name}, msg=sheet successfully loaded!"
        """
    )
