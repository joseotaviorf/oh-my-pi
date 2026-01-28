from argparse import ArgumentParser
from datetime import datetime, timedelta
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql.types import NullType
from pyspark.sql import functions as F

JOB_NAME = "load_reverse_aec"

def cast_void_columns_to_string(df):
    """
    Cast void/null type columns to string to avoid parquet write errors.
    Args:
        df: A dataframe to cast void/null type columns to string.
    Returns:
        A dataframe with void/null type columns cast to string.
    """
    for field in df.schema.fields:
        if isinstance(field.dataType, NullType):
            df = df.withColumn(field.name, F.col(field.name).cast("string"))
    return df

def create_regex_email_filter(organization_filters):
    """
    Create a regex pattern to filter emails from the organization filters.
    Args:
        organization_filters: A string containing the organization names.
    Returns:
        A regex pattern to filter emails from the organization filters.
    """
    orgs = [org.strip().strip("'") for org in organization_filters.strip("()").split(",")]
    patterns = [f"@{org.lower()}.com.br|@{org.lower()}.com" for org in orgs]
    regex_pattern = "(" + "|".join(patterns) + ")$"
    return regex_pattern
  
if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment")
    parser.add_argument("bucket")
    parser.add_argument("dag_name")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("partner_name")
    parser.add_argument("organization_filters")
    
    args = parser.parse_args()

    environment = args.environment
    bucket = args.bucket
    dag_name = args.dag_name
    schema = args.schema
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    partner_name = args.partner_name    
    organization_filters = args.organization_filters

    logger = QuintoAndarLogger(f"{dag_name}")

    # Parse ISO format datetime (supports both date-only and full datetime formats) removing the timezone information
    if 'T' in load_start_date:
        load_start_date = datetime.fromisoformat(load_start_date.replace('+00:00', ''))
    else:
        load_start_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    
    if 'T' in load_end_date:
        load_end_date = datetime.fromisoformat(load_end_date.replace('+00:00', ''))
    else:
        load_end_date = datetime.strptime(load_end_date, "%Y-%m-%d")
    
    # Generate date range
    current_date = load_start_date
    date_range = []
    while current_date <= load_end_date:
        date_range.append(current_date)
        current_date += timedelta(days=1)

    logger.info(
        f"m={JOB_NAME}, source={dag_name}, table_name={table_name}, schema={schema}, "
        f"bucket={bucket}, load_start_date={load_start_date.strftime('%Y-%m-%d')}, "
        f"load_end_date={load_end_date.strftime('%Y-%m-%d')}, "
        f"total_dates={len(date_range)}"
    )

    # Execute process for each date in the range
    for execution_date in date_range:
        execution_date_str = execution_date.strftime("%Y-%m-%d")

        logger.info(
            f"m={JOB_NAME}, source={dag_name}, table_name={table_name}, schema={schema}, "
            f"bucket={bucket}, execution_date={execution_date_str}, "
            f"Starting spark job..."
        )

        try:
            logger.info(f"m=Building dataframe from {schema}.{table_name}, execution_date={execution_date_str}...")
            df = spark.sql(
                f"""
                    SELECT 
                        *,
                        DATE('{execution_date_str}') as execution_date
                    FROM 
                        {schema}.{table_name} 
                    WHERE 
                        year={execution_date.year} 
                        AND month={execution_date.month} 
                        AND day={execution_date.day}
                """
            )

            # get all columns with "organization" in the name
            organization_columns = [col for col in df.columns if "organization" in col.lower()]
            agent_filters = []

            if table_name == 'tickets_perspective':
                # for this table, we only need to filter by the last agent organization
                organization_columns = ['last_agent_organization']
                agent_filters = ['first_agent_email']

            if table_name == 'segments_perspective': 
                agent_filters = ['last_agent_email']
            
            # keep only rows with organization in the organization_filters
            if organization_columns:
                logger.info(f"m=Filtering by organization, columns={organization_columns}, organization_filters={organization_filters}")
                filter_conditions = " OR ".join([f"{col} IN {organization_filters}" for col in organization_columns])
                df = df.filter(filter_conditions)
                logger.info("m=Filter applied successfully")
            else:
                logger.info("m=No organization columns found, skipping filter")
            
            # transform external agent emails from each BPO as non identifiable organization
            if agent_filters:
                logger.info(f"m=Transforming agent email, columns={agent_filters}, organization_filters={organization_filters}")
                regex_pattern = create_regex_email_filter(organization_filters)
                # overwrite value if it doesn't match any organization email
                for column in agent_filters:
                    df = df.withColumn(
                        column,
                        F.when(
                            F.col(column).rlike(regex_pattern),
                            F.col(column)
                        ).otherwise(F.lit("Other Organization Analyst"))
                    )
                logger.info("m=Agent email transformed successfully")
            else:
                logger.info("m=No agent filters found, skipping transformation")

            if df.isEmpty():
                logger.info(f"m=Empty {schema}.{table_name} for execution_date={execution_date_str}!")
            else:
                # extract year, month, day for partitioned path
                year = execution_date.strftime("%Y")
                month = execution_date.strftime("%m")
                day = execution_date.strftime("%d")
                
                # create partitioned S3 path
                s3_path = f"s3a://{bucket}/{partner_name.lower()}/{table_name}/year={year}/month={month}/day={day}/"
                file_name = f"{table_name}_{year}_{month}_{day}.parquet"
                
                try:
                    logger.info(f"m=Loading Dataframe into s3, s3_path={s3_path}")
                    df = cast_void_columns_to_string(df)
                    df.coalesce(1).write.mode("overwrite").parquet(s3_path)
                    logger.info(f"m=Dataframe successfully loaded, s3_path={s3_path}")
                    
                    # Rename the part file to the desired file name
                    logger.info(f"m=Renaming S3 file, s3_path={s3_path}")
                    files = dbutils.fs.ls(s3_path)
                    for f in files:
                        if f.name.startswith("part-") and f.name.endswith(".parquet"):
                            source_path = f.path
                            destination_path = f"{s3_path}{file_name}"
                            dbutils.fs.cp(source_path, destination_path)
                            dbutils.fs.rm(source_path)
                            logger.info(
                                f"m=Successfully renamed S3 file to {file_name}, s3_path={destination_path}"
                            )
                            break
                except Exception as e:
                    logger.error(
                        f"m={JOB_NAME}, execution_date={execution_date_str}, "
                        f"Error writing data to S3, s3_path={s3_path}, error={str(e)}"
                    )
                    raise
            
            logger.info(f"m={JOB_NAME}, execution_date={execution_date_str} completed successfully")
        
        except Exception as e:
            logger.error(
                f"m={JOB_NAME}, execution_date={execution_date_str}, "
                f"Error processing data, error={str(e)}"
            )
            raise
    
    logger.info(f"m={JOB_NAME}, All dates processed successfully, total_dates={len(date_range)}")
    