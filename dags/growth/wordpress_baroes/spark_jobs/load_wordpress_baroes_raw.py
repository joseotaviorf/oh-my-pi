import requests
import math
import datetime as dt

from functools import reduce
from pyspark.sql import DataFrame
from pyspark.sql.functions import regexp_replace
from quintoandar_logger import QuintoAndarLogger
from argparse import ArgumentParser

from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services import JsonService

## Logger
JOB_NAME = "load_wordpress_baroes_raw"
logger = QuintoAndarLogger(JOB_NAME)


## Spark Client
spark_client = SparkClient()
df_service = SparkDataFrameService()


## Funcs
def __generate_date_range(load_start_date, load_end_date):
    """
    This method returns dates standardized to ISO8601 format between start and end date.
    @param load_start_date: Initial date.
    @param load_end_date: Final date.
    @return: Datetime
    """
    start_date = dt.datetime.strptime(load_start_date, "%Y-%m-%d").strftime('%Y-%m-%dT%H:%M:%S.%f%z')
    end_date = (dt.datetime.strptime(load_end_date, "%Y-%m-%d") + dt.timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%S.%f%z')
    
    return start_date, end_date

def __convert_columns_to_string_type(data):
    """
    Converts all columns of a dict or a list of dict to string type.
    :param data: the data that must be converted.
    :type data: dict or list of dict
    """
    converted_data = []
    if isinstance(data, list):
        for item in data:
            converted_data.append(
                JsonService.transform_columns_type_to_string(item)
            )
    else:
        converted_data.append(JsonService.transform_columns_type_to_string(data))

    return converted_data

def __fetch_response_data(get_response):
    """
    Trys to create a spark df from a request.
    @param get_response: get request.
    """
    try:
        response_json = __convert_columns_to_string_type(get_response.json())
        if len(response_json) > 0:
            dataf = spark.createDataFrame([
            { 
                "id": str(row["id"]),
                "date": str(row["date"]),
                "date_gmt": str(row["date_gmt"]),
                "guid": str(row["guid"]),
                "modified": str(row["modified"]),
                "modified_gmt": str(row["modified_gmt"]),
                "slug": str(row["slug"]),
                "status": str(row["status"]),
                "type": str(row["type"]),
                "link": str(row["link"]),
                "title": str(row["title"]),
                "content": str(row["content"]),
                "excerpt": str(row["excerpt"]),
                "author": str(row["author"]),
                "featured_media": str(row["featured_media"]),
                "comment_status": str(row["comment_status"]),
                "ping_status": str(row["ping_status"]),
                "sticky": str(row["sticky"]),
                "template": str(row["template"]),
                "format": str(row["format"]),
                "meta": str(row["meta"]),
                "categories": str(row["categories"]),
                "tags": str(row["tags"]),
                "acf": str(row["acf"]),
                "author_meta": str(row["author_meta"]),
                "featured_img": str(row["featured_img"]),
                "yoast_head": str(row["yoast_head"]),
                "yoast_head_json": str(row["yoast_head_json"]),
                "coauthors": str(row["coauthors"]),
                "tax_additional": str(row["tax_additional"]),
                "comment_count": str(row["comment_count"]),
                "relative_dates": str(row["relative_dates"]),
                "absolute_dates": str(row["absolute_dates"]),
                "absolute_dates_time": str(row["absolute_dates_time"]),
                "featured_img_caption": str(row["featured_img_caption"]),
                "series_order": str(row["series_order"]),
                "wps_subtitle": str(row["wps_subtitle"]),
                "slug_history": str(row["slug_history"]),
                "_links": str(row["_links"])
            } for row in response_json
        ])

            dataf = (df_service
                    .input(dataf)
                    .create_year_month_day_columns_from_dataframe_column("modified")
                    .format_column_names()
                    .output()
                )
            
            return dataf
        
        else:
            logger.info(
                f"""
                m=No retrieved data for {url_request}.
                """
            )

    except Exception as e:
        logger.info(f"Fail convert data. msg={e}")
        raise e


## Spark Job
if __name__ == "__main__":

    ## Parser
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("table_name")
    parser.add_argument("blog")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.env}, source={args.source}, table_name = {args.table_name},
            load_start_date={args.load_start_date}, load_end_date={args.load_end_date},
            blog = {args.blog}
            msg=print spark jobs args
        """
    )


    ## Args
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name
    blog = args.blog


    ## Config Service
    config_service = ConfigurationService(source)
    blog_list = config_service.get_config("blog_list")
    raw_partition_cols = config_service.get_config("raw_partition_cols")


    ## Loaders and Services
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)


    ## Creating database
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)


    ## API get
    if blog in blog_list:
        dfs = []
        endpoint = blog_list[blog]["endpoint"]
        modified_after, modified_before = __generate_date_range(load_start_date,load_end_date)
        page = 1
        per_page = 100

        ## Get data
        url_request = endpoint + f'?page={page}&per_page={per_page}&modified_after={modified_after}&modified_before={modified_before}'
        response = requests.get(url_request)

        if response.status_code == 200:
            totalPosts = int(response.headers.get('X-WP-Total'))

            if totalPosts > per_page:
                pagesRange = range(1,math.ceil(totalPosts/per_page)+1)

                for page in pagesRange: #Limiting pages per call
                    url_request = endpoint + f'?page={page}&per_page={per_page}&modified_after={modified_after}&modified_before={modified_before}'
                    response = requests.get(url_request)

                    dfs.append(__fetch_response_data(response))

            else:
                dfs.append(__fetch_response_data(response))
            
            logger.info(
                f"""
                m=Successfully extract data for {url_request}.
                """
            )
        
        else:
            raise Exception(
                f"""
                m=Failed to extract data for {url_request}.
                Status code={response.status_code}.
                """
            )
            

        ## Loader
        if dfs:
            df = reduce(DataFrame.unionAll, dfs)

            s3_loader.load_df(
                df=df,
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                s3_path=f"{database_location}{table_name}",
                partitions=raw_partition_cols,
                compression="gzip",
            )

            spark_metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                database_location=database_location,
                partitions=raw_partition_cols,
                force_recreate=False,
            )

            spark_metastore_service.create_new_partitions_from_df(
                df=df,
                database_name=database_name,
                table_name=table_name,
                partition_cols=raw_partition_cols,
            )

            logger.info(
                f"""
                m=Successfully save data of {table_name} table.
                load_start_date={args.load_start_date}, load_end_date={args.load_end_date}.
                """
            )

        else:
            logger.info(
                f"""
                m=df empty for {table_name} table.
                initial date {load_start_date}, final date = {load_end_date}
                """
            )
