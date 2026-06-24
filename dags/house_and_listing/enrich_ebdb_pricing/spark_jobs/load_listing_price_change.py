from argparse import ArgumentParser

from delta.tables import DeltaTable
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.window import Window
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_listing_price_change"
logger = QuintoAndarLogger(JOB_NAME)

TABLE_HOUSE_AUD = "datalake_ebdb_clean.house_aud"
TABLE_USER_REVISION = "datalake_ebdb_user.user_revision_entity"
TABLE_LISTING_BUSINESS_CONTEXT = "datalake_ebdb_clean.listing_business_context"


def _get_candidates(start_date, end_date) -> DataFrame:
    """
    Houses with price-relevant audit activity in [start_date, end_date].

    Filters user_revision_entity by ts_revision, then joins with house_aud
    to restrict to records where rent or sale_price > 1.
    Returns a distinct id_house DataFrame used to seed the full-history rebuild.
    """
    r = spark.table(TABLE_USER_REVISION)
    h_aud = spark.table(TABLE_HOUSE_AUD)

    active_revisions = r.filter(
        F.to_date("ts_revision").between(start_date, end_date)
    ).select(F.col("id").alias("rev_id"))

    return (
        h_aud.alias("h")
        .join(active_revisions.alias("rev"), F.col("h.rev") == F.col("rev.rev_id"))
        .filter((F.col("h.rent") > 1) | (F.col("h.sale_price") > 1))
        .select(F.col("h.id_house"))
        .distinct()
    )


def _build_house_aud(candidates: DataFrame) -> DataFrame:
    """
    Joins house audit, revision and listing business context tables for candidate houses.

    Loads the full audit history for each candidate up to CURRENT_DATE - 1 (inclusive),
    independent of the load_start_date / load_end_date window used to select candidates.
    Revisions with ts_revision after that cutoff are excluded so that ts_price_ended and
    is_last_price reflect the state of the world as of D-1. The candidates DataFrame is
    broadcast-joined as a filter seed. Price validity filtering is deferred to
    _build_price_interval per business context.
    """
    history_end_date = F.date_sub(F.current_date(), 1)
    h_aud = spark.table(TABLE_HOUSE_AUD)
    r = spark.table(TABLE_USER_REVISION)
    lbc = spark.table(TABLE_LISTING_BUSINESS_CONTEXT)

    return (
        h_aud.alias("h")
        .join(
            F.broadcast(candidates).alias("c"),
            F.col("h.id_house") == F.col("c.id_house"),
        )
        .join(r.alias("r"), F.col("h.rev") == F.col("r.id"))
        .join(lbc.alias("lbc"), F.col("h.id_house") == F.col("lbc.id_house"))
        .filter((F.col("h.rent") > 1) | (F.col("h.sale_price") > 1))
        .filter(F.to_date(F.col("r.ts_revision")) <= history_end_date)
        .select(
            F.col("h.id_house"),
            F.col("lbc.business_context"),
            F.col("r.id_user").alias("id_user_revision"),
            F.col("h.rev").alias("id_revision"),
            F.col("r.reason").alias("change_reason"),
            F.col("h.rent").alias("rent_price"),
            F.col("h.sale_price"),
            F.col("r.ts_revision"),
        )
    )


def _build_price_interval(
    house_aud_df: DataFrame,
    business_context: str,
    price_col: str,
) -> DataFrame:
    """
    Isolates genuine price changes for a single business context and adds
    ts_price_started / ts_price_ended boundaries.

    Filters out NULL and negative prices upfront so the lag is always computed
    on recorded price values (including zero, which is a valid first price).
    Keeps rows where the price differs from the previous one (or is the first).

    business_context: 'RENT' or 'SALE'.
    price_col: source price column name ('rent_price' or 'sale_price').
    """
    house_window = Window.partitionBy("id_house").orderBy("ts_revision", "id_revision")

    lag_df = (
        house_aud_df.filter(
            (F.col("business_context") == business_context)
            & F.col(price_col).isNotNull()
            & (F.col(price_col) >= 0)
        )
        .select(
            "id_house",
            "business_context",
            "id_user_revision",
            "id_revision",
            "change_reason",
            price_col,
            "ts_revision",
        )
        .withColumn("lag_price", F.lag(price_col).over(house_window))
        .filter(F.col("lag_price").isNull() | (F.col("lag_price") != F.col(price_col)))
    )

    return (
        lag_df.withColumn("ts_price_started", F.col("ts_revision"))
        .withColumn("ts_price_ended", F.lead("ts_revision").over(house_window))
        .drop("ts_revision", "lag_price")
    )


def _prepare_price_changes(price_interval_df: DataFrame, price_col: str) -> DataFrame:
    """
    Maps audit price intervals to the schema expected by _build_variation.

    ts_price_started / ts_price_ended come from _build_price_interval (LEAD over the
    house audit price-change sequence). lag_price is the previous price in that same
    sequence. Listing version windows are not applied.
    """
    house_ts_window = Window.partitionBy("id_house").orderBy(
        "ts_price_started", "id_revision"
    )

    return (
        price_interval_df.withColumn("price", F.col(price_col))
        .withColumn("lag_price", F.lag("price").over(house_ts_window))
        .drop(price_col)
    )


def _build_variation(price_changes_df: DataFrame) -> DataFrame:
    """
    Replicate the rent/sale_price_changes_variation CTEs and the final SELECT
    transformations (rounding, change_number, days_with_pricing_scheme).

    Adds all derived fields from lag_price (consumed here and exposed as previous_price)
    through to the final per-house metrics. Both pipelines (RENT and SALE) are processed
    independently before the union so that change_number is scoped per business context.
    """
    first_price_window = Window.partitionBy("id_house")
    last_price_window = Window.partitionBy("id_house").orderBy(
        F.desc("ts_price_started"), F.desc("id_revision")
    )
    last_price_of_day_window = Window.partitionBy(
        "id_house", F.to_date("ts_price_started")
    ).orderBy(F.desc("ts_price_started"), F.desc("id_revision"))

    # MIN(IF(lag_price IS NULL, price, NULL)) OVER (PARTITION BY id_house)
    # gives the initial (first) price for each house within the current business context.
    first_price_col = F.min(F.when(F.col("lag_price").isNull(), F.col("price"))).over(
        first_price_window
    )

    change_number_window = Window.partitionBy("id_house").orderBy(
        F.asc("ts_price_started"), F.asc("id_revision")
    )

    return (
        price_changes_df.withColumn("previous_price", F.col("lag_price"))
        .withColumn("is_first_price", F.col("lag_price").isNull())
        .withColumn(
            "change_type",
            F.when(F.col("price") - F.col("lag_price") < 0, "PRICE_DECREASE")
            .when(F.col("price") - F.col("lag_price") > 0, "PRICE_INCREASE")
            .otherwise("FIRST_PRICE"),
        )
        .withColumn(
            "last_price_variation",
            F.round(
                (F.col("price") - F.col("lag_price"))
                / F.when(F.col("lag_price") != 0, F.col("lag_price")),
                4,
            ),
        )
        .withColumn("_first_price", first_price_col)
        .withColumn(
            # NULL for the first price record (variation against itself is meaningless);
            # NULLIF-equivalent handled by only computing when ~is_first_price.
            "first_price_variation",
            F.round(
                F.when(
                    ~F.col("is_first_price"),
                    (F.col("price") - F.col("_first_price"))
                    / F.when(F.col("_first_price") != 0, F.col("_first_price")),
                ),
                4,
            ),
        )
        .withColumn(
            "is_last_price_of_day",
            F.row_number().over(last_price_of_day_window) == 1,
        )
        .withColumn(
            "is_last_price",
            F.row_number().over(last_price_window) == 1,
        )
        .withColumn("change_number", F.row_number().over(change_number_window))
        .withColumn(
            "days_with_pricing_scheme",
            F.datediff(
                F.coalesce(F.to_date("ts_price_ended"), F.current_date()),
                F.to_date("ts_price_started"),
            ),
        )
        .drop("lag_price", "_first_price")
    )


def _build_result(house_aud_df: DataFrame) -> DataFrame:
    """
    Assemble the full listing_price_change dataset from both RENT and SALE pipelines,
    union them and append the id_price_change surrogate key.

    house_aud_df must already be persisted by the caller, as it is consumed twice
    (once per business context).
    """
    rent_final = _build_variation(
        _prepare_price_changes(
            _build_price_interval(house_aud_df, "RENT", "rent_price"),
            "rent_price",
        )
    )
    sale_final = _build_variation(
        _prepare_price_changes(
            _build_price_interval(house_aud_df, "SALE", "sale_price"),
            "sale_price",
        )
    )

    return (
        rent_final.unionAll(sale_final)
        .withColumn(
            "id_price_change",
            F.abs(
                F.xxhash64(
                    F.col("id_house"),
                    F.col("id_revision"),
                    F.col("business_context"),
                    F.col("ts_price_started"),
                )
            ),
        )
        .select(
            "id_price_change",
            "id_house",
            "id_user_revision",
            "id_revision",
            "business_context",
            "change_reason",
            "price",
            "previous_price",
            "last_price_variation",
            "first_price_variation",
            "change_type",
            "change_number",
            "days_with_pricing_scheme",
            "is_first_price",
            "is_last_price",
            "is_last_price_of_day",
            "ts_price_started",
            "ts_price_ended",
        )
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="Environment: forno/prod")
    parser.add_argument("datalake_bucket", help="Datalake bucket")
    parser.add_argument("database_name", help="Database base name")
    parser.add_argument("dag_name", help="DAG name")
    parser.add_argument("table_name", help="Target table name")
    parser.add_argument("load_start_date", help="Load start date (YYYY-MM-DD)")
    parser.add_argument("load_end_date", help="Load end date (YYYY-MM-DD)")
    parser.add_argument("run_mode", help="Run mode: prod/dev")

    add_validation_target_args(parser)
    args = parser.parse_args()

    logger.info(
        f"m=__main__, environment={args.environment}, "
        f"database_name={args.database_name}, table_name={args.table_name}, "
        f"msg=Starting {JOB_NAME}"
    )

    start_date = F.lit(args.load_start_date).cast("date")
    end_date = F.lit(args.load_end_date).cast("date")

    candidates = _get_candidates(start_date, end_date)
    candidates_count = candidates.count()
    logger.info(f"m=__main__, candidate_houses={candidates_count:,}")

    if candidates_count == 0:
        logger.warning(
            "m=__main__, msg=No candidate houses found in date range, skipping"
        )
    else:
        house_aud = _build_house_aud(candidates)
        house_aud.persist()

        try:
            result_df = _build_result(house_aud)

            spark_client = SparkClient()
            db_info = DatalakeMetastoreService.get_db_info(
                args.environment, args.database_name, args.datalake_bucket
            )
            database_name = db_info["db_enrich_databricks"]
            database_location = db_info["db_enrich_path"]
            write_database_name, write_table_name, write_location = (
                resolve_datalake_write_target(
                    prod_database=database_name,
                    prod_table=args.table_name,
                    prod_location=database_location,
                    bucket=args.datalake_bucket,
                    target_database=args.target_database_name,
                    target_table=args.target_table_name,
                )
            )

            SparkMetastoreService(spark_client).create_database(write_database_name)

            full_table_name = f"{write_database_name}.{write_table_name}"
            s3_path = (
                f"{write_location}{write_table_name}"
                if write_location.endswith("/")
                else write_location
            )

            # Temp views used in the DELETE condition below.
            # _current_price_changes_in_run: all id_price_change values produced
            #   by this run — the authoritative set for processed houses.
            # _processed_houses_in_run: distinct id_house values in this run —
            #   used to scope the DELETE only to houses the run touched, leaving
            #   all other houses' records untouched.
            result_df.createOrReplaceTempView("_current_price_changes_in_run")
            result_df.select("id_house").distinct().createOrReplaceTempView(
                "_processed_houses_in_run"
            )

            DeltaLoader().load_table(
                table_name=full_table_name,
                path=s3_path,
                source_df=result_df,
                merge_on=["id_price_change"],
            )

            # Step 2: DELETE stale rows — for each processed house, remove any
            # id_price_change that did not appear in this run's result. Without
            # this step those rows would keep their outdated flags indefinitely
            # The condition has two parts:
            #   id_house IN (...):          restrict to houses processed this run;
            #                               records for untouched houses are preserved.
            #   id_price_change NOT IN (...): within those houses, delete only the
            #                               price changes absent from the current result.
            DeltaTable.forName(spark, full_table_name).delete(
                """
                id_house IN (SELECT id_house FROM _processed_houses_in_run)
                AND id_price_change NOT IN (
                    SELECT id_price_change FROM _current_price_changes_in_run
                )
                """
            )

            SparkMetastoreService(spark_client).refresh_table(
                write_database_name, write_table_name
            )
            logger.info(
                f"m=__main__, table={full_table_name}, msg=Load completed successfully"
            )
        finally:
            house_aud.unpersist()
