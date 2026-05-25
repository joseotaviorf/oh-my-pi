"""Spark entrypoint for the HubSpot test ingestion DAG.

The module bundles three responsibilities so the DAG ships as a single Python
file:

  1. CLI parsing and Databricks-secret resolution (``main`` / ``_get_token``).
  2. Per-table configuration (``HubSpotTableConfig``) plus the Spark schemas
     and JSON encoder applied to raw records (``HubSpotEncoder`` /
     ``HubSpotSchemaEnum``).
  3. Extraction and Delta merge orchestration (``HubspotIngestionService``):
     pulls active records (Search-based when supported, paged otherwise),
     optionally augments them with a daily full archived pull, builds a typed
     Spark DataFrame and merges it into the raw Delta table keyed on
     ``(id, updated_at)`` so every API update lands as a new row and the full
     history is preserved at the raw layer.
"""

import json
import logging
from argparse import ArgumentParser
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import List, Optional

import pyspark.sql.functions as F
from pyspark.sql.types import (
    ArrayType,
    BooleanType,
    IntegerType,
    MapType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from quintoandar_hubspot_api_client.clients.hubspot_client import HubspotClient
from quintoandar_hubspot_api_client.factories.endpoint_factory import EndpointFactory
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.json_service import JsonService

JOB_NAME = "load_hubspot_test_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


# --------------------------------------------------------------------- schemas


class HubSpotEncoder(json.JSONEncoder):
    """Serialize HubSpot API records — converting datetimes to ISO 8601 — so that
    `properties`, `properties_with_history` and `associations` payloads can be
    stored as JSON strings on the Delta raw table without losing precision."""

    def default(self, o):
        if isinstance(o, datetime):
            return o.isoformat()
        return json.JSONEncoder.default(self, o)


class HubSpotSchemaEnum(Enum):
    """Spark schemas applied to each table family before writing to the raw layer.

    The shapes mirror what HubSpot's GET endpoints return and what the legacy
    `hubspot` DAG already persists, so downstream queries do not need to change.
    """

    PIPELINE_SCHEMA = StructType(
        [
            StructField("label", StringType(), True),
            StructField("display_order", IntegerType(), True),
            StructField("id", StringType(), True),
            StructField(
                "stages",
                ArrayType(
                    StructType(
                        [
                            StructField("label", StringType(), True),
                            StructField("display_order", IntegerType(), True),
                            StructField(
                                "metadata", MapType(StringType(), StringType()), True
                            ),
                            StructField("id", StringType(), True),
                            StructField("created_at", TimestampType(), True),
                            StructField("archived_at", TimestampType(), True),
                            StructField("updated_at", TimestampType(), True),
                            StructField("archived", BooleanType(), True),
                        ]
                    )
                ),
                True,
            ),
            StructField("created_at", TimestampType(), True),
            StructField("archived_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
        ]
    )
    TEAM_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("user_ids", ArrayType(StringType()), True),
            StructField("secondary_user_ids", ArrayType(StringType()), True),
        ]
    )
    OWNER_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("email", StringType(), True),
            StructField("firstName", StringType(), True),
            StructField("lastName", StringType(), True),
            StructField("user_id", IntegerType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
            StructField(
                "teams",
                ArrayType(
                    StructType(
                        [
                            StructField("id", StringType(), True),
                            StructField("name", StringType(), True),
                            StructField("membership", StringType(), True),
                        ]
                    )
                ),
            ),
            StructField("archived_at", TimestampType(), True),
        ]
    )
    OBJECT_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("properties", StringType(), True),
            StructField("properties_with_history", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
            StructField("archived_at", TimestampType(), True),
            StructField("associations", StringType(), True),
        ]
    )

    @classmethod
    def by_name(cls, schema_name: str) -> "HubSpotSchemaEnum":
        """Resolve a schema by its lowercase name (e.g. ``object``, ``pipeline``)."""
        return cls[f"{schema_name.upper()}_SCHEMA"]


# ---------------------------------------------------------------- table config


@dataclass
class HubSpotTableConfig:
    """Per-table configuration sourced from the DAG declaration."""

    schema: str = "object"
    use_search: bool = True
    bring_archived: bool = False
    encode_inner_dictionaries: bool = True
    properties: List[str] = field(default_factory=list)
    properties_with_history: List[str] = field(default_factory=list)
    associations: List[str] = field(default_factory=list)

    @classmethod
    def from_json(cls, raw: str) -> "HubSpotTableConfig":
        if not raw:
            return cls()
        data = json.loads(raw)
        return cls(
            schema=data.get("schema", "object"),
            use_search=bool(data.get("use_search", True)),
            bring_archived=bool(data.get("bring_archived", False)),
            encode_inner_dictionaries=bool(data.get("encode_inner_dictionaries", True)),
            properties=list(data.get("properties") or []),
            properties_with_history=list(data.get("properties_with_history") or []),
            associations=list(data.get("associations") or []),
        )


# -------------------------------------------------------------- ingestion service


class HubspotIngestionService:
    """Drives a single-table HubSpot extract → Delta merge."""

    DATE_FORMAT = "%Y-%m-%d"

    def __init__(
        self,
        hubspot_client,
        spark_client: Optional[SparkClient] = None,
        delta_loader: Optional[DeltaLoader] = None,
    ) -> None:
        self.hubspot_client = hubspot_client
        self.spark_client = spark_client or SparkClient()
        self.delta_loader = delta_loader or DeltaLoader()
        self.factory = EndpointFactory(hubspot_client)

    def run(
        self,
        environment: str,
        datalake_bucket: str,
        custom_schema: str,
        table_name: str,
        config: HubSpotTableConfig,
        load_start_date: str,
        load_end_date: str,
    ) -> None:
        """End-to-end extraction + write for a single table."""
        logger.info(
            f"m=run, table={table_name}, "
            f"window=[{load_start_date}, {load_end_date}), "
            f"use_search={config.use_search}, "
            f"bring_archived={config.bring_archived}, "
            f"msg=starting ingestion"
        )

        start_ms, end_ms = self._compute_window_ms(load_start_date, load_end_date)

        active_records = self._fetch_active_records(
            table_name=table_name,
            config=config,
            start_ms=start_ms,
            end_ms=end_ms,
            execution_date=load_start_date,
        )
        archived_records = self._fetch_archived_records(
            table_name=table_name, config=config, execution_date=load_start_date
        )

        dataframe = self._build_dataframe(active_records, archived_records, config)
        if dataframe is None:
            logger.info(
                f"m=run, table={table_name}, msg=no records in window — skipping write"
            )
            return

        self._merge_into_delta(
            dataframe=dataframe,
            environment=environment,
            custom_schema=custom_schema,
            datalake_bucket=datalake_bucket,
            table_name=table_name,
            load_start_date=load_start_date,
        )

    @classmethod
    def _compute_window_ms(cls, load_start_date: str, load_end_date: str):
        """Convert ISO date strings into the inclusive/exclusive epoch-ms window
        that HubSpot Search expects."""
        start = datetime.strptime(load_start_date, cls.DATE_FORMAT).replace(
            tzinfo=timezone.utc
        )
        end = datetime.strptime(load_end_date, cls.DATE_FORMAT).replace(
            tzinfo=timezone.utc
        )
        if end <= start:
            # The declaration default already gives a 24h overlap (ds-1 → ds+1);
            # this guard is the safety net for malformed dag_run.conf overrides.
            end = start + timedelta(days=1)
        return int(start.timestamp() * 1000), int(end.timestamp() * 1000)

    def _fetch_active_records(
        self,
        table_name: str,
        config: HubSpotTableConfig,
        start_ms: int,
        end_ms: int,
        execution_date: str,
    ) -> list:
        """Fetch active (non-archived) records for this table.

        Search-capable endpoints use the new server-side filter; everything else
        (owners, pipelines) falls back to the legacy paged consumer.
        """
        consumer = self.factory.build(
            table_name, execution_date, use_search=config.use_search
        )

        if config.use_search:
            return consumer.sync(
                properties=config.properties,
                propertiesWithHistory=config.properties_with_history,
                associations=config.associations,
                start_ms=start_ms,
                end_ms=end_ms,
            )

        kwargs = self._build_paged_kwargs(config)
        return consumer.sync(**kwargs)

    def _fetch_archived_records(
        self, table_name: str, config: HubSpotTableConfig, execution_date: str
    ) -> list:
        """Archived rows are not returned by Search, so when needed they are
        pulled with the paged consumer as a daily full sweep."""
        if not config.bring_archived:
            return []

        paged_consumer = self.factory.build(
            table_name, execution_date, use_search=False
        )
        kwargs = self._build_paged_kwargs(config)
        return paged_consumer.sync(**kwargs, archived=True)

    @staticmethod
    def _build_paged_kwargs(config: HubSpotTableConfig) -> dict:
        """Build the kwargs accepted by HubspotPagedConsumer.sync — only keys
        that the legacy GET endpoints actually understand."""
        kwargs = {}
        if config.properties:
            kwargs["properties"] = config.properties
        if config.properties_with_history:
            kwargs["propertiesWithHistory"] = config.properties_with_history
        if config.associations:
            kwargs["associations"] = config.associations
        return kwargs

    def _build_dataframe(
        self,
        active_records: list,
        archived_records: list,
        config: HubSpotTableConfig,
    ):
        """Convert active + archived records into a single Spark DataFrame."""
        schema = self._resolve_schema(config, active_records or archived_records)
        if schema is None:
            return None

        active_df = self._records_to_dataframe(active_records, schema, config)
        if not archived_records:
            return active_df

        archived_df = self._records_to_dataframe(archived_records, schema, config)
        if active_df is None:
            return archived_df
        if archived_df is None:
            return active_df

        return active_df.unionAll(archived_df).withColumn(
            "updated_at",
            F.greatest(F.col("updated_at"), F.col("archived_at")),
        )

    def _resolve_schema(self, config: HubSpotTableConfig, sample_records: list):
        """Either pick a declared schema or infer a flat one from the records."""
        if config.schema:
            return HubSpotSchemaEnum.by_name(config.schema).value
        if not sample_records:
            return None
        return self._infer_flat_schema(sample_records)

    @staticmethod
    def _infer_flat_schema(records: list) -> StructType:
        """Fallback for tables without a declared schema: every field is a
        string except `created_at` / `updated_at` which become timestamps."""
        fields = []
        for column_name in records[0].keys():
            if column_name in ("created_at", "updated_at"):
                fields.append(StructField(column_name, TimestampType()))
            else:
                fields.append(StructField(column_name, StringType()))
        return StructType(fields)

    def _records_to_dataframe(
        self, records: list, schema: StructType, config: HubSpotTableConfig
    ):
        if not records:
            return None
        if config.encode_inner_dictionaries:
            records = JsonService.transform_json_list_terms(records, cls=HubSpotEncoder)
        return self.spark_client.create_dataframe(records, schema)

    def _merge_into_delta(
        self,
        dataframe,
        environment: str,
        custom_schema: str,
        datalake_bucket: str,
        table_name: str,
        load_start_date: str,
    ) -> None:
        """Append-only merge keyed on (id, updated_at) so every API update lands
        as a new row and we preserve full history at the raw layer."""
        db_info = DatalakeMetastoreService.get_db_info(
            environment, custom_schema, datalake_bucket
        )
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]

        ts_load = datetime.strptime(load_start_date, self.DATE_FORMAT).replace(
            tzinfo=timezone.utc
        )
        dataframe = dataframe.withColumn("ts_load", F.lit(ts_load))

        if dataframe.rdd.isEmpty():
            logger.info(
                f"m=_merge_into_delta, table={table_name}, "
                f"msg=DataFrame is empty after enrichment — skipping write"
            )
            return

        self.delta_loader.load_table(
            table_name=f"{database_name}.{table_name}",
            path=f"{database_location}{table_name}",
            source_df=dataframe,
            merge_on=["id", "updated_at"],
        )
        logger.info(
            f"m=_merge_into_delta, table={database_name}.{table_name}, "
            f"msg=merge completed"
        )


# ------------------------------------------------------------------ entrypoint


def main():
    args = parse_arguments()
    logger.info(
        f"m=main, environment={args.env}, datalake_bucket={args.datalake_bucket}, "
        f"source={args.source}, custom_schema={args.custom_schema}, "
        f"load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, "
        f"table={args.table}, msg=starting Spark job"
    )

    config = HubSpotTableConfig.from_json(args.table_config)
    hubspot_client = HubspotClient(_get_token())
    service = HubspotIngestionService(hubspot_client=hubspot_client)

    service.run(
        environment=args.env,
        datalake_bucket=args.datalake_bucket,
        custom_schema=args.custom_schema,
        table_name=args.table,
        config=config,
        load_start_date=args.load_start_date,
        load_end_date=args.load_end_date,
    )


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("custom_schema")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("table")
    parser.add_argument(
        "table_config",
        help=("JSON-encoded per-table HubSpot config (see HubSpotTableConfig)."),
    )
    return parser.parse_args()


def _get_token() -> str:
    """Resolve the HubSpot OAuth token from Databricks secrets."""
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    if dbutils is None:
        raise RuntimeError(
            "m=_get_token, msg=dbutils is not available — "
            "this job must run on a Databricks cluster"
        )

    json_credentials = dbutils.secrets.get(scope="quintoandar", key=APIEnum.HUBSPOT)
    return json.loads(json_credentials)["token"]


if __name__ == "__main__":
    main()
