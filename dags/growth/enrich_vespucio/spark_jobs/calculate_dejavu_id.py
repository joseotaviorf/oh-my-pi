import json
import s2cell
import logging
import requests
import unidecode
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
from pyspark.sql.window import Window
from pyspark.sql.functions import udf, col, expr, row_number

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "calculate_dejavu_id"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _prepare_address(row):
    """
    This function prepares and formats an address from a given data row.

    Parameters:
    row (dict): A dictionary containing address components. The keys of interest are 
    "id_address", "source", "address", "number", "neighborhood", "zip_code", and "city".

    Returns:
    dict: A new dictionary with the keys "id_address", "source", and "input_address". 
    "id_address" and "source" are copied from the input row. "input_address" is a string containing the 
    concatenated address components separated by commas.
    """
    desired_keys = [
        "address",
        "number",
        "neighborhood",
        "zip_code",
        "city"
    ]

    return {
        "id_address": row["id_address"],
        "source": row["source"],
        "input_address": ", ".join([row[key] for key in desired_keys if row[key]])
    }

def _extract_address_components(response):
    """"
    This function extracts address components from a given API response.
    
    Parameters:
    response (tuple): A tuple containing the status of the API request and the data returned by and
    API request.

    Returns:
    dict: A dictionary containing the address components. The keys are "id_address", "input_address",
    "geocode_address", "address", "number", "zip_code", "neighborhood", "city", "state", and "country".
    """

    address_components = {
        'route': 'address',
        'postal_code': 'zip_code',
        'street_number': 'number',
        'sublocality_level_1': 'neighborhood',
        'administrative_area_level_2': 'city',
        'administrative_area_level_1': 'state',
        'country': 'country'
    }

    address_info = {}

    for component in response.get('address_components', []):
        
        for api_type, key in address_components.items():
        
            if api_type in component['types']:
        
                if api_type == 'administrative_area_level_1':
                    address_info[key] = component.get('short_name')
        
                else:
                    address_info[key] = component.get('long_name')
    
    return address_info


def _make_api_request(api_keys, input):
    """
    This function makes an API request to the Google Maps Geocoding API.

    Parameters:
    api_keys (dict): A dictionary containing API keys. The keys of the dictionary should 
    correspond to the sources of the addresses. The function will use the source from the input 
    data to select the corresponding API key.

    input (dict): A dictionary containing the address data. It should have the following keys:
    "source", "id_address", and "input_address". 

    "source" is used to select the corresponding API key from the `api_keys` dictionary. 
    "id_address" and "input_address" are used in the returned data if a valid geocode result is 
    obtained or if an error occurs.

    Returns:
    tuple: A tuple with two elements -> The status of the API request and the data returned by and 
    API request.
    """

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
        "key": api_keys[input["source"]],
        "address": input["input_address"]
    }

    base_url = "https://maps.googleapis.com/maps/api/geocode/json?"

    try:
        response = requests.get(base_url, params=params).json()
        
        if response["status"] == "OK":
            results = response["results"]
            best_geocode_match = sorted(results, key=get_priority, reverse=True)[0]
            address_info = _extract_address_components(best_geocode_match)

            return (
                True,
                (
                    input["id_address"],
                    input["input_address"],
                    best_geocode_match["formatted_address"],
                    address_info.get('address'),
                    address_info.get('number'),
                    address_info.get('zip_code'),
                    address_info.get('neighborhood'),
                    address_info.get('city'),
                    address_info.get('state'),
                    address_info.get('country'),
                    float(best_geocode_match["geometry"]["location"]["lat"]),
                    float(best_geocode_match["geometry"]["location"]["lng"]),
                    datetime.now()
                )
            ) 
        else:
            return (False, response["status"], input)
    except Exception as e:
        return (False, (e, input))
    
def _s2cell_udf(lat, lng):

    """
    This function converts a pair of latitude and longitude coordinates into an S2Cell token.

    The S2 geometry library is a spatial indexing system that divides the Earth's surface into 
    cells identified by a token. This function uses the S2Cell library to perform the conversion.

    Parameters:
    lat (float): The latitude of the point.
    lng (float): The longitude of the point.

    Returns:
    str or None: The S2Cell token corresponding to the input coordinates. If the input is None or 
    if an error occurs during the conversion, the function returns None.
    """
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
    parser.add_argument("requests_limit", help="requests_limit")
    
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    context = args.context
    addresses_s2_geometry_mapping_table = args.addresses_s2_geometry_mapping_table
    requests_limit = args.requests_limit

    logger.info(
        f"""m=__main__, environment={environment},
        datalake_bucket={datalake_bucket}, dag_name={dag_name}, context={context}
        """
    )

    spark_client = SparkClient()

    schema = StructType([
        StructField("id_address", StringType(), nullable=False),
        StructField("input_address", StringType(), nullable=False),
        StructField("output_address", StringType(), nullable=False),
        StructField("address", StringType(), nullable=True),
        StructField("number", StringType(), nullable=True),
        StructField("zip_code", StringType(), nullable=True),
        StructField("neighborhood", StringType(), nullable=True),
        StructField("city", StringType(), nullable=True),
        StructField("state", StringType(), nullable=True),
        StructField("country", StringType(), nullable=True),
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

    """
    We will create a query with the two solutions: Vespúcio and ITBI.
    We will make it clear in the query so that we can discriminate each request.
    """
    query = """
        WITH condo AS (
                SELECT DISTINCT
                    id_address,
                    'vespucio' AS source,
                    address,
                    number,
                    neighborhood,
                    zip_code,
                    city
                FROM
                    datalake_vespucio.condo_full
            ),
            itbi AS (
                SELECT 
                    id_address,
                    'itbi' AS source,
                    address,
                    number,
                    neighborhood,
                    zipcode,
                    city
                FROM 
                    datalake_itbi_addresses.itbi_sp
                UNION ALL 
                SELECT 
                    id_address,
                    'itbi' AS source,
                    address,
                    number,
                    neighborhood,
                    zipcode,
                    city
                FROM 
                    datalake_itbi_addresses.itbi_bh
            ),
            union_solutions AS (
                SELECT 
                    *
                FROM 
                    condo 
                UNION ALL 
                SELECT 
                    *
                FROM 
                    itbi
            )
            SELECT
                u.id_address,
                u.source,
                u.address,
                CAST(u.number AS STRING) AS number,
                u.neighborhood,
                u.zip_code,
                u.city
            FROM
                union_solutions AS u
            LEFT JOIN
                {database_name}.{addresses_s2_geometry_mapping_table} AS s2
                ON u.id_address = s2.id_address
            WHERE
                s2.id_dejavu IS NULL
                OR DATEDIFF(CURRENT_TIMESTAMP(), s2.ts_updated) > 30
            ORDER BY 
                u.source DESC
            LIMIT 
                {requests_limit}
    """.format(
        database_name=database_name,
        addresses_s2_geometry_mapping_table=addresses_s2_geometry_mapping_table,
        requests_limit=requests_limit
    )

    df = spark_client.conn.sql(query)
    
    df_addresses = [_prepare_address(row.asDict()) for row in df.collect()]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    """
    We will use the same credential with 2 different API Keys, where each solution has its own key.
    With this, depending on the source of each line, the cost will be split.
    
    Example:
      {
          "vespucio": "API_KEY_VESPUCIO",     
          "itbi": "API_KEY_ITBI",
      }
    """    
    api_keys = json.loads(unidecode.unidecode(dbutils.secrets.get(scope="quintoandar", key=APIEnum.GOOGLE_GEOCODING)))
    api_responses = [_make_api_request(api_keys, address) for address in df_addresses]

    successes = []
    failures = []
    for res in api_responses:
        if res[0]:
            successes.append(res[1])
        else:
            failures.append(res[1:3])

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
                f"source={condo_info['source']}, "
                f"input_address={condo_info['input_address']}, "
                f"exception={exception}"
            )

    try:
        """
        We will now create:
            The id_dejavu which is based on the S2Cell token.
            The geographic points which are created from the latitude and longitude by the Sedona library.
        """
        calculate_dejavu_id = udf(_s2cell_udf, StringType())
        new_data = spark_client.conn.createDataFrame(successes, schema)
        new_data = new_data.withColumn("id_dejavu", calculate_dejavu_id(new_data.latitude, new_data.longitude))
        new_data = new_data.withColumn("points", expr("ST_Point(CAST(longitude AS Decimal(24,20)), CAST(latitude AS Decimal(24,20)))"))

        """
        We retrieve the polygons via query
        """
        polygons_query = """
            SELECT
                CAST(r.id AS INTEGER) AS id_region,
                ST_PolygonFromText(REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(pr.polygon, 'POLYGON', ''), '[\\(\\)]', ''), ' ', ','), ',') AS polygon,
                r.ts_created AS ts_region_created
            FROM
                datalake_ebdb_clean.polygon_region AS pr
            JOIN
                datalake_ebdb_clean.map_region AS r
                    ON r.id = pr.id_region
            WHERE
                r.level = 'SubRegiao'
        """
        polygons = spark_client.conn.sql(polygons_query)
        
        """
        We will now join the new data with the polygons to get the id_region.
        """
        new_data_with_region = new_data.join(polygons, expr("ST_Within(points, polygon)"), how = 'left')

        new_data_with_region_dedup = (new_data_with_region
                                      .withColumn("polygon_order", row_number().over(Window.partitionBy("id_address").orderBy("ts_region_created")))
                                      .filter("polygon_order = 1"))
        
        column_order = ["id_dejavu", "id_address", "id_region", "input_address", "output_address", "address", "number", "zip_code", "neighborhood", "city", "state", "country","latitude", "longitude", "ts_updated"]
        new_data_reordered = new_data_with_region_dedup.select(column_order)

        df1 = spark_client.conn.table(f"{database_name}.{addresses_s2_geometry_mapping_table}")
        df2 = new_data_reordered.select("id_address")

        """
        We will now join the new data with the existing data to check if there are any new addresses.
        """
        joined_df = df1.join(df2.alias("new"), df1.id_address == col("new.id_address"), "left")
        filtered_df = joined_df.filter(col("new.id_address").isNull()).drop(col("new.id_address"))
        
        result_df = new_data_reordered.union(filtered_df)

        """
        We will now save the results in the database and update the metastore.
        """
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