from argparse import ArgumentParser
import logging

from pyspark.sql import DataFrame, Window
from pyspark.sql.functions import (
    col, concat_ws, current_timestamp, greatest, least, lit, md5,
    row_number, when, max as sql_max, min as sql_min, sum as sql_sum,
    size, reverse, array_union, array
)
from pyspark.sql.types import StringType

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_hierarchy_closure"
logger = logging.getLogger(JOB_NAME)

MAX_HIERARCHY_LEVELS = 9


def load_base_relationships(spark_client: SparkClient) -> DataFrame:
    """Load base manager-employee relationships from datalake_pin.managers_history"""
    query = """
        SELECT DISTINCT
            assignment_number,
            employee_name,
            manager_assignment_number,
            manager_name,
            dt_effective_started,
            dt_effective_ended
        FROM datalake_pin.managers_history
        WHERE manager_assignment_number IS NOT NULL
            AND manager_assignment_number != '300000008488092'
    """
    df = spark_client.conn.sql(query)
    base_count = df.count()
    logger.info(f"Loaded {base_count:,} base relationships")
    return df


def build_level(
    base_df: DataFrame,
    previous_level_df: DataFrame,
    level: int
) -> DataFrame:
    """
    Build the next level of hierarchy by joining the previous level
    with base relationships on manager_assignment_number
    """ 
    next_level = previous_level_df.alias("prev") \
        .join(
            base_df.alias("base"),
            col("prev.manager_assignment_number_chain").getItem(level - 2) == col("base.assignment_number"),
            "inner"
        ) \
        .select(
            col("prev.assignment_number").alias("assignment_number"),
            col("prev.employee_name").alias("employee_name"),
            col("prev.manager_assignment_number_chain").alias("manager_assignment_number_chain"),
            col("prev.manager_name_chain").alias("manager_name_chain"),
            col("prev.dt_started").alias("dt_started"),
            col("prev.dt_ended").alias("dt_ended"),
            col("base.manager_assignment_number").alias(f"new_manager_assignment_{level}"),
            col("base.manager_name").alias(f"new_manager_name_{level}"),
            col("base.dt_effective_started").alias(f"new_dt_started_{level}"),
            col("base.dt_effective_ended").alias(f"new_dt_ended_{level}")
        )
    
    next_level = next_level.withColumn(
        "manager_assignment_number_chain",
        array_union(
            col("manager_assignment_number_chain"),
            array(col(f"new_manager_assignment_{level}"))
        )
    ).withColumn(
        "manager_name_chain",
        array_union(
            col("manager_name_chain"),
            array(col(f"new_manager_name_{level}"))
        )
    ).withColumn(
        "dt_started",
        greatest(col("dt_started"), col(f"new_dt_started_{level}"))
    ).withColumn(
        "dt_ended",
        least(col("dt_ended"), col(f"new_dt_ended_{level}"))
    ).filter(
        col("dt_started") < col("dt_ended")
    ).select(
        "assignment_number",
        "employee_name",
        "manager_assignment_number_chain",
        "manager_name_chain",
        "dt_started",
        "dt_ended"
    )
    
    level_count = next_level.count()
    logger.info(f"Level {level} produced {level_count:,} records")
    return next_level


def initialize_level_1(base_df: DataFrame) -> DataFrame:
    """Initialize the first level of hierarchy with direct managers"""   
    level_1 = base_df.select(
        col("assignment_number"),
        col("employee_name"),
        array(col("manager_assignment_number")).alias("manager_assignment_number_chain"),
        array(col("manager_name")).alias("manager_name_chain"),
        col("dt_effective_started").alias("dt_started"),
        col("dt_effective_ended").alias("dt_ended")
    )
    level_1_count = level_1.count()
    logger.info(f"Level 1 initialized with {level_1_count:,} records")
    return level_1


def build_iterative_hierarchy(spark_client: SparkClient) -> DataFrame:
    """Build the complete hierarchy by iterating through levels"""
    base_df = load_base_relationships(spark_client)
    
    level_1 = initialize_level_1(base_df)
    all_levels = level_1
    current_level = level_1
    
    for level in range(2, MAX_HIERARCHY_LEVELS + 1):
        next_level = build_level(base_df, current_level, level)
        
        if next_level.count() == 0:
            logger.info(f"No more records at level {level}, stopping iteration")
            break
        
        all_levels = all_levels.union(next_level)
        current_level = next_level
    
    total_count = all_levels.count()
    logger.info(f"Total records across all levels: {total_count:,}")
    return all_levels


def pivot_hierarchy_to_columns(df: DataFrame) -> DataFrame:
    """
    Transform array columns into individual lX columns.
    l0 = CEO (top of hierarchy), highest lX = direct manager
    """    
    df = df.withColumn("manager_assignment_number_chain", reverse(col("manager_assignment_number_chain")))
    df = df.withColumn("manager_name_chain", reverse(col("manager_name_chain")))
    df = df.withColumn("chain_length", size(col("manager_name_chain")))
    
    for i in range(MAX_HIERARCHY_LEVELS + 1):
        df = df.withColumn(
            f"assignment_number_l{i}",
            when(col("chain_length") > i, col("manager_assignment_number_chain").getItem(i))
            .otherwise(lit(None).cast(StringType()))
        )
        df = df.withColumn(
            f"name_l{i}",
            when(col("chain_length") > i, col("manager_name_chain").getItem(i))
            .otherwise(lit(None).cast(StringType()))
        )
    
    select_cols = ["assignment_number", "employee_name"]
    for i in range(MAX_HIERARCHY_LEVELS + 1):
        select_cols.extend([f"name_l{i}", f"assignment_number_l{i}"])
    select_cols.extend(["dt_started", "dt_ended"])
    
    df = df.select(*select_cols)
    logger.info("Pivoting completed")
    return df


def consolidate_consecutive_periods(df: DataFrame) -> DataFrame:
    """
    Consolidate consecutive periods with identical hierarchies.
    Merge rows where dt_ended of one row equals dt_started of the next row
    and all hierarchy columns are identical.
    """
    logger.info("Consolidating consecutive periods with identical hierarchies...")
    
    hierarchy_cols = []
    for i in range(MAX_HIERARCHY_LEVELS + 1):
        hierarchy_cols.extend([f"name_l{i}", f"assignment_number_l{i}"])
    
    df = df.withColumn(
        "hierarchy_signature",
        concat_ws("|", *[col(c) for c in hierarchy_cols])
    )
    
    # Create window specs for looking at previous/next records
    window_prev = Window.partitionBy("assignment_number", "hierarchy_signature")\
        .orderBy("dt_started").rowsBetween(Window.unboundedPreceding, -1)
    window_next = Window.partitionBy("assignment_number", "hierarchy_signature")\
        .orderBy("dt_started").rowsBetween(1, Window.unboundedFollowing)
    
    df = df.withColumn("prev_dt_ended", sql_max("dt_ended").over(window_prev))
    df = df.withColumn("next_dt_started", sql_min("dt_started").over(window_next))
    
    # Group consecutive periods - mark the start of a new group when dates don't connect
    df = df.withColumn(
        "is_new_group",
        when(
            (col("prev_dt_ended").isNull()) | (col("dt_started") != col("prev_dt_ended")),
            lit(1)
        ).otherwise(lit(0))
    )
    
    df = df.withColumn(
        "group_id",
        sql_sum("is_new_group").over(Window.partitionBy("assignment_number").orderBy("dt_started"))
    )
    
    # Aggregate by group
    group_cols = ["assignment_number", "employee_name", "group_id"] + hierarchy_cols
    df_consolidated = df.groupBy(*group_cols).agg(
        sql_min("dt_started").alias("dt_started"),
        sql_max("dt_ended").alias("dt_ended")
    ).drop("group_id", "hierarchy_signature")
    
    consolidated_count = df_consolidated.count()
    original_count = df.count()
    logger.info(f"Consolidated from {original_count:,} to {consolidated_count:,} records")
    
    return df_consolidated


def add_scd_type2_fields(df: DataFrame) -> DataFrame:
    """Add SCD Type 2 fields: version, is_current, ts_load, sk_hierarchy"""
    
    window_spec = Window.partitionBy("assignment_number").orderBy("dt_started")
    
    df = df.withColumn("version", row_number().over(window_spec))
    df = df.withColumn(
        "is_current",
        when(col("dt_ended") == lit("4712-12-31"), lit(True)).otherwise(lit(False))
    )
    df = df.withColumn("ts_load", current_timestamp())
    df = df.withColumn(
        "sk_hierarchy",
        md5(concat_ws("_", col("assignment_number"), col("version")))
    )
    
    logger.info("Added SCD Type 2 fields")
    return df


def select_final_columns(df: DataFrame) -> DataFrame:
    """Select and order final columns for output"""
    select_cols = ["sk_hierarchy", "assignment_number", "employee_name"]
    for i in range(MAX_HIERARCHY_LEVELS + 1):
        select_cols.extend([f"name_l{i}", f"assignment_number_l{i}"])
    select_cols.extend(["dt_started", "dt_ended", "version", "is_current", "ts_load"])
    
    return df.select(*select_cols)


def build_hierarchical_closure(spark_client: SparkClient) -> DataFrame:
    """Main pipeline to build the complete hierarchical closure"""
    logger.info("Starting hierarchical closure build...")
    
    df = build_iterative_hierarchy(spark_client)
    df = pivot_hierarchy_to_columns(df)
    df = consolidate_consecutive_periods(df)
    df = add_scd_type2_fields(df)
    df = select_final_columns(df)
    
    logger.info("Hierarchical closure build completed")
    return df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="Environment: forno/prod")
    parser.add_argument("datalake_bucket", type=str, help="Datalake bucket name")
    parser.add_argument("source", type=str, help="Source schema name")
    parser.add_argument("context", type=str, help="Context/table name")
    parser.add_argument("execution_date", type=str, help="Execution date")
    
    args = parser.parse_args()
    
    logger.info(
        f"m=__main__, environment={args.env}, source={args.source}, context={args.context}, "
        f"datalake_bucket={args.datalake_bucket}, execution_date={args.execution_date}, "
        f"msg=Starting Spark job..."
    )
    
    spark_client = SparkClient()
    
    # Build the hierarchy
    df_hierarchy = build_hierarchical_closure(spark_client)
    
    # Get database info
    db_info = DatalakeMetastoreService.get_db_info(args.env, args.source, args.datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    
    # Create database if not exists
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)
    
    # Load to Delta
    table_name = args.context
    s3_path = database_location + table_name
    full_table_name = f"{database_name}.{table_name}"
    
    logger.info(f"Table {full_table_name} will be loaded as Delta.")
    
    delta_loader = DeltaLoader()
    delta_loader.load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=df_hierarchy,
    )
    
    spark_metastore_service.refresh_table(database_name, table_name)

    # Apply table privileges
    table_privileges_dict = {"people-analytics": ["ALL PRIVILEGES"]}

    table_privileges = TablePrivileges.from_input_dict(
        table_privileges_dict,
        full_table_name,
    )
    table_privileges.apply()
    logger.info(
        f"Applied privileges on {full_table_name} for: {list(table_privileges_dict.keys())}"
    )

    logger.info(f"Successfully loaded {df_hierarchy.count():,} records to {full_table_name}")

