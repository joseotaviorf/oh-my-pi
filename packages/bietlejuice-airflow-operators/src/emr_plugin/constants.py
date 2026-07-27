"""Shared defaults for QuintoAndar EMR Airflow operators."""

EMR_DEFAULT_POOL = "emr_api"
EMR_DEFAULT_POOL_SLOTS = 1
EMR_DEFAULT_WAITER_DELAY_SECONDS = 30
# Set high on purpose so the Airflow task-level ``execution_timeout`` is what
# ends a runaway EMR wait, not the boto waiter. With the default
# ``waiter_delay=30``, this yields ~83h budget — larger than any realistic
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
