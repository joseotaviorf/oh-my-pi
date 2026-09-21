"""Shared defaults for QuintoAndar EMR Airflow operators."""

EMR_DEFAULT_POOL = "emr_api"
EMR_DEFAULT_POOL_SLOTS = 1
EMR_DEFAULT_WAITER_DELAY_SECONDS = 30
# Step waits poll DescribeStep on this quantum; a 26-28s sync/register step showed as a
# 62s Airflow task at 30s. 15s halves that overhead on ~470k short steps per fortnight.
# Cluster create/terminate keep the 30s default (one call per DAG run).
EMR_DEFAULT_STEP_WAITER_DELAY_SECONDS = 15
# Set high on purpose so the Airflow task-level ``execution_timeout`` is what
# ends a runaway EMR wait, not the boto waiter. With the default
# ``waiter_delay=30`` (or 15 for steps, ~41h budget), this is larger than any realistic
# ``execution_timeout_hours`` configured on bi-etl-ejuice DAGs. Callers can
# still pass a smaller value per task.
EMR_DEFAULT_WAITER_MAX_ATTEMPTS = 10000

EMR_INSTANCE_GROUP_NAME_MASTER = "Master nodes"
EMR_INSTANCE_GROUP_NAME_CORE = "Core nodes"
EMR_INSTANCE_GROUP_NAME_TASK = "Task nodes"
DEFAULT_MASTER_INSTANCE_TYPE = "m5.xlarge"

EMR_INSTANCE_FLEET_NAME_MASTER = "Master fleet"
EMR_INSTANCE_FLEET_NAME_CORE = "Core fleet"
EMR_INSTANCE_FLEET_NAME_TASK = "Task fleet"
DEFAULT_SPOT_TIMEOUT_MINUTES = 10
# Product requirement: fleets must always fall back to on-demand rather than
# terminating the cluster when spot capacity can't be provisioned in time.
# Intentionally NOT exposed as a YAML-configurable value.
EMR_FLEET_SPOT_TIMEOUT_ACTION = "SWITCH_TO_ON_DEMAND"

# Spark graceful decommission, injected into spark-defaults whenever a
# translated cluster has spot capacity (fleet TargetSpotCapacity or an
# instance-group Market=SPOT). When AWS reclaims a spot node, YARN opens a
# ~2-min decommission window; these let Spark migrate shuffle/RDD blocks off
# the dying executor so a running stage can finish. spark.decommission.enabled
# is the master switch (Spark 3.1+; EMR 7.12 ships Spark 3.5) — without it the
# spark.storage.decommission.* keys are no-ops. Harmless on on-demand-only
# clusters, so we still skip those to keep RunJobFlow payloads unchanged.
SPOT_DECOMMISSION_PROPERTIES = {
    "spark.decommission.enabled": "true",
    "spark.storage.decommission.enabled": "true",
    "spark.storage.decommission.shuffleBlocks.enabled": "true",
    "spark.storage.decommission.rddBlocks.enabled": "true",
}

# Required both for Priority to be honoured and to exceed the 5-instance-type fleet cap (up to 30).
EMR_FLEET_ON_DEMAND_ALLOCATION_STRATEGY = "prioritized"

# Airflow Variable name for Google Chat capacity failure alert webhook.
EMR_CAPACITY_ALERT_WEBHOOK_VARIABLE = "GCHAT_BROKEN_DAG_WEBHOOK"
