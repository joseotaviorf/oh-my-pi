from datetime import datetime
from typing import Dict, List, Optional

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.functions import col, lit

CDC_COLUMNS = ["op_cdc", "ts_database_transaction", "ts_cdc_transaction"]

# Hibernate Envers on the transactional (CDC) layer shares one revision-entity
# table and one column-naming convention across every entity's ``*_aud``
# table (``contrato_aud``, and any future ``<entity>_aud``): the revision
# metadata always lives in ``usuariorevisionentity``, keyed by the same
# ``REV`` / ``rEVTYPE`` / ``motivo`` / ``usuario_id`` / ``timestamp`` (epoch
# ms) columns. Per-entity ``aud_config`` blocks therefore only need to declare
# ``aud_table``, ``aud_id_col`` (both entity-specific) and ``enabled`` --
# see ``HistoricalHelper.resolve_aud_config``. Any key below can still be
# overridden explicitly (e.g. to target the clean AUD layer instead).
DEFAULT_TRANSACTIONAL_ENVERS_CONFIG: Dict[str, object] = {
    "revision_entity_table": "datalake_ebdb_transactional.usuariorevisionentity",
    "revision_reason_col": "motivo",
    "revision_pk_col": "REV",
    "revision_type_col": "rEVTYPE",
    "revision_entity_id_col": "id",
    "revision_user_id_col": "usuario_id",
    "revision_ts_col": "timestamp",
    "revision_ts_is_epoch_ms": True,
}


class HistoricalHelper:
    """Reusable helper for core model historical tables.

    Provides utilities for loading data from the CDC transactional layer
    and enriching DataFrames with CDC metadata columns. Any core model
    Spark job can import this helper to build historical tracking tables
    without modifying the CDC pipeline itself.
    """

    @staticmethod
    def load_transactional_data(
        spark: SparkSession,
        table_name: str,
        args,
        date_column: str = "ts_database_transaction",
    ) -> DataFrame:
        """Load data from a CDC transactional table with date-range filtering.

        Args:
            spark: SparkSession instance
            table_name: Fully qualified transactional table name
                (e.g. ``datalake_company_transactional.company``)
            args: Parsed job arguments containing load_start_date / load_end_date
            date_column: Column to filter on (default ``ts_database_transaction``)

        Returns:
            DataFrame filtered to the requested date range
        """
        df = spark.read.table(table_name)

        if (
            args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        ):
            df = df.filter(
                (
                    col(date_column).cast("date")
                    >= lit(args.load_start_date).cast("date")
                )
                & (
                    col(date_column).cast("date")
                    <= lit(args.load_end_date).cast("date")
                )
            )

            # Transactional tables are partitioned by integer columns year/month/day
            # (and optionally hour). Spark cannot prune those partitions via a
            # timestamp predicate alone, so a full table scan is performed even when
            # the date range is narrow. Add an explicit integer-partition filter
            # when those columns are present so that only the relevant Parquet
            # files are opened — this is essential when any partition outside the
            # requested window has missing or corrupted S3 files.
            if "year" in df.columns and "month" in df.columns and "day" in df.columns:
                start = datetime.strptime(args.load_start_date, "%Y-%m-%d")
                end = datetime.strptime(args.load_end_date, "%Y-%m-%d")
                start_ymd = start.year * 10000 + start.month * 100 + start.day
                end_ymd = end.year * 10000 + end.month * 100 + end.day
                df = df.filter(
                    (
                        F.col("year") * 10000 + F.col("month") * 100 + F.col("day")
                        >= start_ymd
                    )
                    & (
                        F.col("year") * 10000 + F.col("month") * 100 + F.col("day")
                        <= end_ymd
                    )
                )

        return df

    @staticmethod
    def resolve_aud_config(aud_config: Dict) -> Dict:
        """Merge entity-specific ``aud_config`` overrides onto the shared
        transactional Hibernate Envers defaults
        (``DEFAULT_TRANSACTIONAL_ENVERS_CONFIG``).

        Every entity's transactional AUD source is expected to share the same
        revision-entity table and Envers column-naming convention, so a
        per-entity ``aud_config`` block only needs to declare ``aud_table``,
        ``aud_id_col`` and ``enabled``. Any other key present in
        ``aud_config`` still wins over the default (e.g. to point an entity
        still on the clean AUD layer at ``user_revision_entity`` / ``rev_type``
        / ``mod_*`` naming instead).
        """
        return {**DEFAULT_TRANSACTIONAL_ENVERS_CONFIG, **aud_config}

    @staticmethod
    def load_aud_revision_data(
        spark: SparkSession,
        aud_config: Dict,
        args,
    ) -> Optional[DataFrame]:
        """Load AUD revision data joined with user_revision_entity.

        Reads the AUD table (Hibernate Envers) and LEFT JOINs with
        ``user_revision_entity`` to attach revision metadata (reason, user id).
        Only rows within the load window are returned. The returned DataFrame
        is de-duplicated by ``(aud_id_col, ts_database_transaction, rev)`` and
        is broadcast-eligible for the ``user_revision_entity`` slice.

        The AUD table always has ``op_cdc='c'`` (Envers issues INSERT-only CDC
        events). ``ts_database_transaction`` is the original source-DB transaction
        timestamp, matching the transactional CDC stream exactly.

        Args:
            spark: SparkSession instance
            aud_config: Dict with keys:
                - ``aud_table``: fully qualified AUD table name (required,
                  entity-specific, no default)
                - ``aud_id_col``: entity id column in the AUD table (required,
                  entity-specific, no default)
                - ``enabled``: bool flag; if False returns None
                - All other keys fall back to
                  ``DEFAULT_TRANSACTIONAL_ENVERS_CONFIG`` (the shared
                  transactional Envers convention) unless explicitly overridden:
                  ``revision_entity_table``, ``revision_reason_col``,
                  ``revision_pk_col``, ``revision_entity_id_col``,
                  ``revision_user_id_col``, ``revision_ts_col``,
                  ``revision_ts_is_epoch_ms``.
            args: Parsed job arguments with load_start_date / load_end_date

        Returns:
            DataFrame with columns:
            ``{aud_id_col}``, ``ts_database_transaction``, ``rev``, ``rev_type``,
            all ``mod_*`` boolean columns, ``ts_revision``, ``revision_reason``,
            ``aud_user_id``; or ``None`` when ``aud_config.enabled`` is False.
        """
        if not aud_config.get("enabled", False):
            return None

        resolved_config = HistoricalHelper.resolve_aud_config(aud_config)

        aud_table = resolved_config["aud_table"]
        revision_entity_table = resolved_config["revision_entity_table"]
        revision_reason_col = resolved_config["revision_reason_col"]
        revision_pk_col = resolved_config["revision_pk_col"]
        revision_entity_id_col = resolved_config["revision_entity_id_col"]
        revision_user_id_col = resolved_config["revision_user_id_col"]
        revision_ts_col = resolved_config["revision_ts_col"]
        revision_ts_is_epoch_ms = resolved_config["revision_ts_is_epoch_ms"]

        aud_df = spark.read.table(aud_table)

        if (
            args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        ):
            aud_df = aud_df.filter(
                (
                    col("ts_database_transaction").cast("date")
                    >= lit(args.load_start_date).cast("date")
                )
                & (
                    col("ts_database_transaction").cast("date")
                    <= lit(args.load_end_date).cast("date")
                )
            )

            if (
                "year" in aud_df.columns
                and "month" in aud_df.columns
                and "day" in aud_df.columns
            ):
                start = datetime.strptime(args.load_start_date, "%Y-%m-%d")
                end = datetime.strptime(args.load_end_date, "%Y-%m-%d")
                start_ymd = start.year * 10000 + start.month * 100 + start.day
                end_ymd = end.year * 10000 + end.month * 100 + end.day
                aud_df = aud_df.filter(
                    (
                        F.col("year") * 10000 + F.col("month") * 100 + F.col("day")
                        >= start_ymd
                    )
                    & (
                        F.col("year") * 10000 + F.col("month") * 100 + F.col("day")
                        <= end_ymd
                    )
                )

        # Restrict the revision-entity slice to only the revision IDs that appear
        # in the already date-filtered aud_df window. The full table can be ~100M
        # rows; broadcasting it unfiltered risks OOM or exceeding
        # spark.sql.autoBroadcastJoinThreshold on production loads.
        rev_ids_in_window = aud_df.select(
            col(revision_pk_col).alias("_rev_filter_id")
        ).distinct()

        ts_revision_expr = HistoricalHelper._revision_ts_expr(
            revision_ts_col, revision_ts_is_epoch_ms
        )

        ure_df = (
            spark.read.table(revision_entity_table)
            .select(
                col(revision_entity_id_col).alias("_ure_id"),
                col(revision_reason_col).alias("revision_reason"),
                ts_revision_expr,
                col(revision_user_id_col).alias("aud_user_id"),
            )
            .join(
                rev_ids_in_window,
                on=col("_ure_id") == rev_ids_in_window["_rev_filter_id"],
                how="inner",
            )
            .drop("_rev_filter_id")
        )

        # NOTE (known limitation — safe for incremental loads, revisit for backfills):
        # The broadcast below is only sized for the load window. ``ure_df`` is bounded
        # by ``rev_ids_in_window``, which is bounded by the date-filtered ``aud_df``.
        # On a normal incremental (narrow-window) run that slice is small, so the
        # broadcast is cheap and safe. On a *wide-window backfill*
        # (``load_start_date``..``load_end_date`` spanning months/years), the slice
        # scales with the window and the broadcast can again exceed
        # ``spark.sql.autoBroadcastJoinThreshold`` and OOM the driver. We are NOT
        # fixing this now; a later deployment should size-gate the hint (drop
        # ``F.broadcast`` and let AQE choose SortMergeJoin above a row/byte threshold)
        # before running large backfills through this path.
        aud_with_ure = aud_df.join(
            F.broadcast(ure_df),
            on=aud_df[revision_pk_col] == ure_df["_ure_id"],
            how="left",
        ).drop("_ure_id")

        return aud_with_ure

    @staticmethod
    def load_aud_revision_datasets(
        spark: SparkSession,
        aud_configs: List[Dict],
        args,
    ) -> Dict[str, DataFrame]:
        """Load multiple named AUD sources for a single history entity.

        A history table can be enriched from more than one AUD table (e.g.
        house field changes from ``imovel_aud`` and owner changes from
        ``imovellistingrelation_aud``). Each ``aud_configs`` entry is a
        standalone ``aud_config`` dict (same shape accepted by
        ``load_aud_revision_data``) plus a required, unique ``name`` used to
        route ``event_configs`` entries to their AUD source via the
        ``aud_source`` key.

        Args:
            spark: SparkSession instance
            aud_configs: List of ``aud_config`` dicts, each with a unique
                ``name`` in addition to the keys documented on
                ``load_aud_revision_data``.
            args: Parsed job arguments with load_start_date / load_end_date

        Returns:
            Dict mapping each enabled entry's ``name`` to its loaded AUD
            DataFrame. Entries with ``enabled: false`` are omitted.

        Raises:
            ValueError: If an entry is missing ``name`` or two entries share
                the same ``name``.
        """
        aud_dfs: Dict[str, DataFrame] = {}
        seen_names = set()
        for i, aud_config in enumerate(aud_configs):
            name = aud_config.get("name")
            if name is None or str(name).strip() == "":
                raise ValueError(f"aud_configs[{i}] must include a non-empty 'name'")
            name = str(name).strip()
            if name in seen_names:
                raise ValueError(f"aud_configs[{i}] has duplicate name: {name!r}")
            seen_names.add(name)

            aud_df = HistoricalHelper.load_aud_revision_data(spark, aud_config, args)
            if aud_df is not None:
                aud_dfs[name] = aud_df

        return aud_dfs

    @staticmethod
    def _revision_ts_expr(revision_ts_col: str, is_epoch_ms: bool):
        """Build the ``ts_revision`` column expression for revision-entity joins.

        Clean ``user_revision_entity`` stores ``ts_revision`` as TIMESTAMP.
        Transactional ``usuariorevisionentity`` exposes raw epoch-ms ``timestamp``
        and needs the same migration fix applied in the clean pipeline.
        """
        if not is_epoch_ms:
            return col(revision_ts_col).cast("timestamp").alias("ts_revision")

        raw_ts = col(revision_ts_col)
        fixed_ts_ms = F.when(
            raw_ts < F.lit(20000000000000),
            raw_ts,
        ).otherwise(
            F.unix_timestamp(raw_ts.cast("string"), "yyyyMMddHHmmss") * F.lit(1000)
        )
        return F.timestamp_millis(fixed_ts_ms.cast("long")).alias("ts_revision")

    @staticmethod
    def select_cdc_columns(transactional_df: DataFrame, alias: str) -> list:
        """Return CDC column expressions from a transactional DataFrame.

        Args:
            transactional_df: DataFrame loaded from a transactional table
            alias: Table alias used in the join (e.g. ``"c"``)

        Returns:
            List of Column expressions for ``op_cdc``, ``ts_database_transaction``
            and ``ts_cdc_transaction``
        """
        return [col(f"{alias}.{c}") for c in CDC_COLUMNS]
