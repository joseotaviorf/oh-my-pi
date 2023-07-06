import s2cell
import logging
import requests
from datetime import datetime
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.api import APIEnum
from bietlejuice.base.spark import BaseDBUtils

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql.types import StructType, StructField, DoubleType, StringType, TimestampType
from pyspark.sql.functions import udf, col

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "calculate_dejavu_id"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _prepare_address(row):
    desired_keys = [
        "address",
        "number",
        "neighborhood",
        "zip_code",
        "city"
    ]

    return {
        "address_type": row["address_type"],
        "id_address": row["id_address"],
        "complete_address": ", ".join([row[key] for key in desired_keys if row[key]])
    }

def _make_api_request(api_key, input):

    def get_priority(dictionary):
        location_type = dictionary.get("location_type")
        return priorities.get(location_type, 0)

    priorities = {
        "ROOFTOP": 4,
        "RANGE_INTERPOLATED": 3,
        "GEOMETRIC_CENTER": 2,
        "APPROXIMATE": 1
    }

    params = {
        "key": api_key,
        "address": input["complete_address"]
    }

    base_url = "https://maps.googleapis.com/maps/api/geocode/json?"

    try:
        response = requests.get(base_url, params=params).json()
        
        if response["status"] == "OK":
            results = response["results"]
            best_geocode_match = sorted(results, key=get_priority, reverse=True)[0]
            return (
                True,
                (
                    input["address_type"],
                    input["id_address"],
                    input["complete_address"],
                    best_geocode_match["geometry"]["location"]["lat"],
                    best_geocode_match["geometry"]["location"]["lng"],
                    datetime.now()
                )
            ) 
        else:
            return (False, response["status"], input)
    except Exception as e:
        return (False, (e, input))
    
def _s2cell_udf(lat, lng):
  if(lat and lng):
    try:
        code = s2cell.lat_lon_to_cell_id(lat, lng, 22)
        return s2cell.cell_id_to_token(code)
    except Exception as e:
        raise Exception(
            f"Exception trying to obtain s2cell token, "
            f"exception={e}"
        )
  return None

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="datalake_bucket")
    parser.add_argument("dag_name", help="dag_name")
    parser.add_argument("context", help="context")
    parser.add_argument("addresses_s2_geometry_mapping_table", help="addresses_s2_geometry_mapping_table")
    
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    context = args.context
    addresses_s2_geometry_mapping_table = args.addresses_s2_geometry_mapping_table

    logger.info(
        f"""m=__main__, environment={environment},
        datalake_bucket={datalake_bucket}, dag_name={dag_name}, context={context}
        """
    )

    spark_client = SparkClient()

    schema = StructType([
        StructField("address_type", StringType(), nullable=False),
        StructField("id_address", StringType(), nullable=False),
        StructField("complete_address", StringType(), nullable=False),
        StructField("latitude", DoubleType(), nullable=True),
        StructField("longitude", DoubleType(), nullable=True),
        StructField("ts_updated", TimestampType(), nullable=False)
    ])

    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(environment, context, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    spark_metastore_service.create_database(database_name)

    query = """
        SELECT
            "condo" AS address_type,
            c.uuid AS id_address,
            c.address,
            c.number,
            c.neighborhood,
            c.zip_code,
            c.city
        FROM
            datalake_vespucio.condo_full c
        LEFT JOIN
            {database_name}.{addresses_s2_geometry_mapping_table} s2
            ON s2.address_type = "condo"
                AND c.uuid = s2.id_address
        WHERE
            s2.id_dejavu IS NULL
            OR DATEDIFF(CURRENT_TIMESTAMP(), s2.ts_updated) > 30
        LIMIT 1000
    """.format(
        database_name=database_name,
        addresses_s2_geometry_mapping_table=addresses_s2_geometry_mapping_table
    )

    df = spark_client.conn.sql(query)

    df_addresses = [_prepare_address(row.asDict()) for row in df.collect()]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    api_key = dbutils.secrets.get(scope="quintoandar", key=APIEnum.GOOGLE_GEOCODING)

    api_responses = [_make_api_request(api_key, address) for address in df_addresses]

    successes = []
    failures = []
    for res in api_responses:
        if res[0]:
            successes.append(res[1])
        else:
            failures.append(res[1])

    logger.info(
        f"m=__main__, msg=Total Geocoding API successful results: {len(successes)} "
        f"Total failed results: {len(failures)}"
    )

    """
    This will give detailed logs in case we aren"t able to
    obtain a lat/lng for some address.
    """
    if len(failures):
        for failure in failures:
            exception, condo_info = failure
            logger.error(
                f"id_address={condo_info['id_address']}, "
                f"address_type={condo_info['address_type']}, "
                f"complete_address={condo_info['complete_address']}, "
                f"exception={exception}"
            )

    try:
        calculate_dejavu_id = udf(_s2cell_udf, StringType())
        new_data = spark_client.conn.createDataFrame(successes, schema)
        new_data = new_data.withColumn("id_dejavu", calculate_dejavu_id(new_data.latitude, new_data.longitude))
        new_data = new_data.drop(*["latitude", "longitude"])
        column_order = ["id_dejavu", "address_type", "id_address", "complete_address", "ts_updated"]
        new_data_reordered = new_data.select(column_order)

        df1 = spark_client.conn.table(f"{database_name}.{addresses_s2_geometry_mapping_table}").filter("address_type = 'condo'")
        df2 = new_data_reordered.select("id_address")

        joined_df = df1.join(df2.alias("new"), df1.id_address == col("new.id_address"), "left")
        filtered_df = joined_df.filter(col("new.id_address").isNull()).drop(col("new.id_address"))

        result_df = new_data_reordered.union(filtered_df)

        s3_loader.load_df(
            df=result_df,
            format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
            s3_path=f"{database_location}{addresses_s2_geometry_mapping_table}",
        )

        spark_metastore_loader.update_metastore(
            df=result_df,
            database_name=database_name,
            table_name=addresses_s2_geometry_mapping_table,
            format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
            database_location=database_location,
        )
    except Exception as e:
        raise Exception(
            f"Exception trying to save Dejavu Id, "
            f"exception={e}"
        )