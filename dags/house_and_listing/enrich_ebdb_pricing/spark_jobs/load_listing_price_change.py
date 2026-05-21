from argparse import ArgumentParser

from delta.tables import DeltaTable
from pyspark.sql import DataFrame, functions as F
from pyspark.sql.window import Window

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_listing_price_change"
logger = QuintoAndarLogger(JOB_NAME)

TABLE_HOUSE_AUD = "datalake_ebdb_clean.house_aud"
TABLE_USER_REVISION = "datalake_ebdb_user.user_revision_entity"
TABLE_LISTING_BUSINESS_CONTEXT = "datalake_ebdb_clean.listing_business_context"
TABLE_HOUSE_LISTING = "datalake_ebdb_listing.house_listing"
TABLE_BUSINESS_CONTEXT_HISTORY = "datalake_ebdb_listing.business_context_history"
TABLE_SALE_LISTING_STATUS = "datalake_sale_listings.sale_listing_status"


def _get_candidates(start_date, end_date) -> DataFrame:
    """
    Houses with price-relevant audit activity in [start_date, end_date].

    Filters user_revision_entity by ts_revision, then joins with house_aud
    to restrict to records where rent or sale_price > 1.
    Returns a distinct id_house DataFrame used to seed the full-history rebuild.
    """
    r = spark.table(TABLE_USER_REVISION)
    h_aud = spark.table(TABLE_HOUSE_AUD)

    active_revisions = (
        r.filter(F.to_date("ts_revision").between(start_date, end_date))
        .select(F.col("id").alias("rev_id"))
    )

    return (
        h_aud.alias("h")
        .join(active_revisions.alias("rev"), F.col("h.rev") == F.col("rev.rev_id"))
        .filter((F.col("h.rent") > 1) | (F.col("h.sale_price") > 1))
        .select(F.col("h.id_house"))
        .distinct()
    )


def _build_house_aud(candidates: DataFrame, end_date) -> DataFrame:
    """
    Joins house audit, revision and listing business context tables for candidate houses.

    Loads the full audit history for each candidate up to end_date (inclusive), so that
    the output reflects the state of the world as of D-1. Revisions with ts_revision > end_date
    are excluded so that ts_price_ended and is_last_price are computed relative to the same
    date boundary. The candidates DataFrame is broadcast-joined as a filter seed.
    Price validity filtering is deferred to _build_price_interval per business context.
    """
    h_aud = spark.table(TABLE_HOUSE_AUD)
    r = spark.table(TABLE_USER_REVISION)
    lbc = spark.table(TABLE_LISTING_BUSINESS_CONTEXT)

    return (
        h_aud.alias("h")
        .join(F.broadcast(candidates).alias("c"), F.col("h.id_house") == F.col("c.id_house"))
        .join(r.alias("r"), F.col("h.rev") == F.col("r.id"))
        .join(lbc.alias("lbc"), F.col("h.id_house") == F.col("lbc.id_house"))
        .filter((F.col("h.rent") > 1) | (F.col("h.sale_price") > 1))
        .filter(F.to_date(F.col("r.ts_revision")) <= end_date)
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

    Filters out NULL prices upfront so the lag is always computed on recorded
    price values (including zero, which is a valid first price). Keeps rows
    where the price differs from the previous one (or is the first).

    business_context: 'RENT' or 'SALE'.
    price_col: source price column name ('rent_price' or 'sale_price').
    """
    house_window = Window.partitionBy("id_house").orderBy("ts_revision", "id_revision")

    lag_df = house_aud_df.filter(
        (F.col("business_context") == business_context) & F.col(price_col).isNotNull()
    ).select(
        "id_house", "business_context", "id_user_revision", "id_revision",
        "change_reason", price_col, "ts_revision",
    ).withColumn(
        "lag_price", F.lag(price_col).over(house_window)
    ).filter(
        F.col("lag_price").isNull() | (F.col("lag_price") != F.col(price_col))
    )

    return (
        lag_df
        .withColumn("ts_price_started", F.col("ts_revision"))
        .withColumn("ts_price_ended", F.lead("ts_revision").over(house_window))
        .drop("ts_revision", "lag_price")
    )


def _build_rent_listing_versions() -> DataFrame:
    """
    Finds distinct (house, listing, version window) triples for RENT listings via a
    range join, then marks which is the earliest version per house.
    """
    hl = spark.table(TABLE_HOUSE_LISTING)
    bch = spark.table(TABLE_BUSINESS_CONTEXT_HISTORY)

    join_cond = (
        (F.col("hl.id_house") == F.col("bch.id_house"))
        & (F.col("hl.ts_listing_version_start") <= F.col("bch.ts_state_started"))
        & (
            F.coalesce(F.col("bch.ts_state_ended"), F.current_timestamp())
            <= F.coalesce(F.col("hl.ts_listing_version_end"), F.current_timestamp())
        )
    )

    versions = (
        hl.filter(F.col("id_house_listing").isNotNull()).alias("hl")
        .join(bch.filter(F.col("business_context") == "RENT").alias("bch"), join_cond)
        .select(
            F.col("hl.id_house"),
            F.col("hl.id_house_listing"),
            F.col("hl.ts_listing_version_start"),
            F.col("hl.ts_listing_version_end"),
        )
        .distinct()
    )

    house_window = Window.partitionBy("id_house").orderBy(F.asc("ts_listing_version_start"))

    return versions.withColumn(
        "is_first_version",
        F.row_number().over(house_window) == 1,
    )


def _build_sale_listing_versions() -> DataFrame:
    """
    For each sale listing, derives the full lifecycle:
    - ts_listing_version_start: earliest ts_status_started (MIN over the listing)
    - ts_listing_version_end: ts_status_ended of the latest status row, i.e. the row
      with the maximum COALESCE(ts_status_ended, CURRENT_TIMESTAMP) — NULL when the
      listing is still active.
    """
    sale_status = spark.table(TABLE_SALE_LISTING_STATUS)

    listing_window = Window.partitionBy("id_sale_listing")
    latest_end_window = (
        Window
        .partitionBy("id_sale_listing")
        .orderBy(F.desc(F.coalesce(F.col("ts_status_ended"), F.current_timestamp())))
        .rowsBetween(Window.unboundedPreceding, Window.unboundedFollowing)
    )
    house_window = Window.partitionBy("id_house").orderBy(F.asc("ts_listing_version_start"))

    return (
        sale_status.filter(F.col("id_sale_listing").isNotNull())
        .withColumn("ts_listing_version_start", F.min("ts_status_started").over(listing_window))
        .withColumn("ts_listing_version_end", F.first("ts_status_ended").over(latest_end_window))
        .select(
            F.col("id_house"),
            F.col("id_sale_listing").alias("id_house_listing"),
            F.col("ts_listing_version_start"),
            F.col("ts_listing_version_end"),
        )
        .distinct()
        .withColumn("is_first_version", F.row_number().over(house_window) == 1)
    )


def _build_price_changes_listing(
    price_interval_df: DataFrame,
    listing_versions_df: DataFrame,
    price_col: str,
) -> DataFrame:
    """
    Joins price intervals to their corresponding listing version window using the logic
    of first-version back-fill vs standard overlap check, then computes lag_price for
    the joined result.

    price_col: name of the price column in price_interval_df ('rent_price' or 'sale_price').
    """
    pi = price_interval_df.alias("pi")
    lv = listing_versions_df.alias("lv")

    ts_price_ended_coalesced = F.coalesce(
        F.col("pi.ts_price_ended"), F.current_timestamp()
    )
    ts_version_end_coalesced = F.coalesce(
        F.col("lv.ts_listing_version_end"), F.current_timestamp()
    )

    join_cond = (
        (F.col("lv.id_house") == F.col("pi.id_house"))
        & F.when(
            F.col("lv.is_first_version")
            & (F.col("pi.ts_price_started") < F.col("lv.ts_listing_version_start")),
            (F.col("lv.ts_listing_version_start") >= F.col("pi.ts_price_started"))
            & (F.col("lv.ts_listing_version_start") <= ts_price_ended_coalesced),
        ).otherwise(
            (F.col("pi.ts_price_started") >= F.col("lv.ts_listing_version_start"))
            & (F.col("pi.ts_price_started") < ts_version_end_coalesced),
        )
    )

    joined = (
        pi.join(lv, join_cond)
        .select(
            F.col("pi.id_house"),
            F.col("lv.id_house_listing"),
            F.col("pi.id_user_revision"),
            F.col("pi.id_revision"),
            F.col("pi.business_context"),
            F.col("pi.change_reason"),
            F.col(f"pi.{price_col}").alias("price"),
            F.col("pi.ts_price_started"),
        )
    )

    house_ts_window = Window.partitionBy("id_house").orderBy("ts_price_started", "id_revision")

    # ts_price_ended is recomputed here (post-JOIN) so it only references events
    # that survived the listing-version filter. Computing it from the pre-JOIN
    # LEAD in _build_price_interval would let it point to audit events excluded
    # by the JOIN, producing a non-null ts_price_ended for the last effective price.
    return (
        joined
        .withColumn("lag_price", F.lag("price").over(house_ts_window))
        .withColumn("ts_price_ended", F.lead("ts_price_started").over(house_ts_window))
    )


def _build_variation(listing_df: DataFrame) -> DataFrame:
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
    last_price_of_day_window = (
        Window
        .partitionBy("id_house", F.to_date("ts_price_started"))
        .orderBy(F.desc("ts_price_started"), F.desc("id_revision"))
    )

    # MIN(IF(lag_price IS NULL, price, NULL)) OVER (PARTITION BY id_house)
    # gives the initial (first) price for each house within the current business context.
    first_price_col = F.min(
        F.when(F.col("lag_price").isNull(), F.col("price"))
    ).over(first_price_window)

    change_number_window = Window.partitionBy("id_house").orderBy(
        F.asc("ts_price_started"), F.asc("id_revision")
    )

    return (
        listing_df
        .withColumn("previous_price", F.col("lag_price"))
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
    rent_listing = _build_price_changes_listing(
        _build_price_interval(house_aud_df, "RENT", "rent_price"),
        _build_rent_listing_versions(),
        "rent_price",
    )
    sale_listing = _build_price_changes_listing(
        _build_price_interval(house_aud_df, "SALE", "sale_price"),
        _build_sale_listing_versions(),
        "sale_price",
    )

    rent_final = _build_variation(rent_listing)
    sale_final = _build_variation(sale_listing)

    return (
        rent_final.unionAll(sale_final)
        .withColumn(
            "id_price_change",
            F.abs(F.xxhash64(
                F.col("id_house"),
                F.col("id_revision"),
                F.col("business_context"),
                F.col("ts_price_started"),
            )),
        )
        .select(
            "id_price_change",
            "id_house",
            "id_house_listing",
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
        house_aud = _build_house_aud(candidates, end_date)
        house_aud.persist()

        try:
            result_df = _build_result(house_aud)

            spark_client = SparkClient()
            db_info = DatalakeMetastoreService.get_db_info(
                args.environment, args.database_name, args.datalake_bucket
            )
            database_name = db_info["db_enrich_databricks"]
            database_location = db_info["db_enrich_path"]

            SparkMetastoreService(spark_client).create_database(database_name)

            full_table_name = f"{database_name}.{args.table_name}"
            s3_path = f"{database_location}{args.table_name}"

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
                database_name, args.table_name
            )
            logger.info(
                f"m=__main__, table={full_table_name}, "
                f"msg=Load completed successfully"
            )
        finally:
            house_aud.unpersist()
