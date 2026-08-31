"""Volume metrics for the Salesforce CDC dead-letter (DLQ) replay.

The DLQ does not get a metric table of its own. It appends to the shared
``datalake_sst_metrics.events_type_volume`` under a metric-only
``event_type = 'DLQ_RECOVERY'``, so DLQ volume sits next to the regular CDC
event types and the existing dashboards keep working. Lake rows stay
``RECOVERY`` — the type the AppFlow API fallback also uses — so the two
recovery paths remain distinguishable in the metric without renaming anything
in the lake.
"""

from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.metrics import save_volume_metric

logger = QuintoAndarLogger("sst.domains.salesforce.recovery.volume")

DLQ_EVENT_TYPE = "DLQ_RECOVERY"
VOLUME_METRIC_NAME = "events_type_volume"
VOLUME_METRIC_GRAIN = ["partition_date", "partition_hour", "event_type"]


def save_dlq_volume_metrics(
    spark,
    bucket,
    target_table,
    env,
    partition_date,
    partition_hour,
    raw_df=None,
    clean_df=None,
):
    """Append one ``DLQ_RECOVERY`` row per layer for this partition.

    ``raw_df`` counts records fetched from the Salesforce API and upserted into
    raw; ``clean_df`` counts the CDC history replayed into clean. The two need
    not match — one recovered ID can carry many history rows.

    A ``None`` frame means the DLQ returned early for that layer (no missing
    IDs, or no API query to send). It still has to land as ``row_count = 0``:
    every run writes both layers, so an *absent* row means the ``dlq_events_*``
    task did not run, which is a different problem from having nothing to
    recover.
    """
    for layer, df in (("raw", raw_df), ("clean", clean_df)):
        logger.info(f"m=save_dlq_volume_metrics, msg=Saving {layer} DLQ volume")
        save_volume_metric(
            spark=spark,
            df=(
                None
                if df is None
                else stamp_dlq_event_type(df, partition_date, partition_hour)
            ),
            grain=VOLUME_METRIC_GRAIN,
            metric_name=VOLUME_METRIC_NAME,
            table_name=target_table,
            env=env,
            layer=layer,
            partition_cols=["partition_date", "partition_hour"],
            table_location=f"s3a://{bucket}/sst_metrics/{VOLUME_METRIC_NAME}",
            fallback_grain_values={
                "partition_date": partition_date,
                "partition_hour": partition_hour,
                "event_type": DLQ_EVENT_TYPE,
            },
        )


def stamp_dlq_event_type(df, partition_date, partition_hour):
    """Tag a metric-only copy with ``DLQ_RECOVERY``; lake rows stay ``RECOVERY``."""
    return (
        df.withColumn("partition_date", F.lit(partition_date))
        .withColumn("partition_hour", F.lit(partition_hour))
        .withColumn("event_type", F.lit(DLQ_EVENT_TYPE))
    )
