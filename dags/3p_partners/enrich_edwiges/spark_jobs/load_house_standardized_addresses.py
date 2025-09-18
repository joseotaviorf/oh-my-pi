from argparse import ArgumentParser, Namespace
from typing import Dict, Any
import json
from pyspark.sql.functions import (
    col, udf, when, isnan, isnull, get_json_object, lit, coalesce, 
    concat_ws, current_timestamp
)
from pyspark.sql.types import StringType
from pyspark.sql import DataFrame

# Edwiges imports
from edwiges.address_standardizer import parse_address, parse_zipcode
from edwiges.complement_interpreter import ComplementInterpreter
from edwiges import __version__ as edwiges_version

# Bietlejuice imports
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_standardized_addresses"

def main():
    """Main function to process addresses using Edwiges"""
    args = parse_args()
    # Load source data
    houses_df = load_source_data()
    
    # Apply Edwiges transformations
    standardized_df = apply_edwiges_transformations(houses_df)
    
    # Save results
    save_df(standardized_df, args)

def parse_args() -> Namespace:
    """Parse arguments passed to the job"""
    
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument("database_base_name", type=str, help="base name for database")
    parser.add_argument("relative_query_path", type=str, help="relative query path for sql file to create table")
    parser.add_argument("table_name", type=str, help="table name that will be created")

    return parser.parse_args()

def load_source_data() -> DataFrame:
    """Load house data from datalake_house_clean.house"""
    query = """
        SELECT 
            id AS id_house,
            id_region,
            city AS city_name,
            status AS house_status,
            address,
            zipcode AS zip_code,
            number AS house_number,
            neighborhood,
            complement,
            total_area,
            lat,
            lng,
            dt_creation AS ts_created,
            ts_updated
        FROM
            datalake_ebdb_clean.house
        WHERE
            address IS NOT NULL
            AND TRIM(address) != ''
    """
    
    return spark.sql(query)

def create_edwiges_udfs():
    """Create Spark UDFs for Edwiges functions"""
    
    @udf(returnType=StringType())
    def standardize_address_udf(address_str):
        """UDF to standardize address using Edwiges"""
        if address_str is None or str(address_str).strip() == "":
            return None
        try:
            return parse_address(str(address_str))
        except Exception as e:
            # Return error with prefix for debugging
            return f"ERROR: {str(e)}"
    
    @udf(returnType=StringType())
    def standardize_zipcode_udf(zipcode_str):
        """UDF to standardize zipcode using Edwiges"""
        if zipcode_str is None or str(zipcode_str).strip() == "":
            return None
        try:
            return parse_zipcode(str(zipcode_str))
        except Exception as e:
            return None
    
    @udf(returnType=StringType())
    def interpret_complement_udf(complement_str):
        """UDF to interpret complement using Edwiges"""
        if complement_str is None or str(complement_str).strip() == "":
            return None
        try:
            ci = ComplementInterpreter()
            result = ci.interpret(str(complement_str))
            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            return json.dumps({"error": str(e), "input": str(complement_str)})
    
    return standardize_address_udf, standardize_zipcode_udf, interpret_complement_udf

def apply_edwiges_transformations(df: DataFrame) -> DataFrame:
    """Apply Edwiges transformations to the DataFrame"""
    
    # Create UDFs
    standardize_address_udf, standardize_zipcode_udf, interpret_complement_udf = create_edwiges_udfs()
    
    # Apply Edwiges processing and create the required schema
    result_df = df.withColumn(
        "address_raw", 
        col("address")
    ).withColumn(
        "address", 
        standardize_address_udf(col("address"))
    ).withColumn(
        "zipcode_raw", 
        col("zip_code")
    ).withColumn(
        "zipcode", 
        standardize_zipcode_udf(col("zip_code"))
    ).withColumn(
        "number_raw", 
        col("house_number")
    ).withColumn(
        "number", 
        # Extract and clean house number - could be enhanced with Edwiges
        when(col("house_number").isNotNull(), col("house_number").cast("string"))
        .otherwise(None)
    ).withColumn(
        "complement_raw", 
        col("complement")
    ).withColumn(
        "complement_analysis", 
        interpret_complement_udf(col("complement"))
    )
    
    # Add metadata columns
    result_df = result_df.withColumn(
        "ts_load",
        current_timestamp()
    ).withColumn(
        "edwiges_version",
        lit(edwiges_version)
    )
    
    # Select final columns in the required order
    final_df = result_df.select(
        col("id_house"),
        col("id_region"),
        col("city_name"),
        col("address"),
        col("address_raw"),
        col("zipcode"),
        col("zipcode_raw"),
        col("number"),
        col("number_raw"),
        col("neighborhood"),
        col("complement_analysis"),
        col("complement_raw"),
        col("total_area"),
        col("lat"),
        col("lng"),
        col("edwiges_version"),
        col("ts_created"),
        col("ts_updated"),
        col("ts_load")
    )
    
    return final_df

def save_df(df: DataFrame, args: Namespace) -> None:
    """Saves dataframe to enrich layer"""

    spark_client = SparkClient()
    loader = DeltaLoader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(args.env, args.database_base_name, args.datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    spark_metastore_service.create_database(database_name)
    s3_path = database_location + args.table_name
    full_table_name = f"{database_name}.{args.table_name}"

    loader.load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=df
    )
    spark_metastore_service.refresh_table(
            database_name, args.table_name
    )

    table_privileges = TablePrivileges.from_environment_default(full_table_name)
    if (
        table_privileges
        and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
    ):
        table_privileges.apply()

if __name__ == "__main__":
    main()