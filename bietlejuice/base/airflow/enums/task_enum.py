from enum import Enum


class TaskEnum(Enum):
    DATA_QUALITY_TESTS = "data_quality_tests"
    DUMMY_JOB_CLUSTER_FINISHED = "dummy_job_cluster_finished"
    EXECUTE_JOB_CLUSTER = "execute_job_cluster"
    GENERATE_POSTGRES_TABLE_METRICS = "generate_postgres_table_metrics"
    LOAD_CDC_CLEAN = "load_cdc_clean"
    LOAD_CDC_RAW = "load_cdc_raw"
    LOAD_CDC_TRANSACTIONAL = "load_cdc_transactional"
    LOAD_MONGO_RAW = "load_mongo_raw"
    LOAD_POSTGRES_RAW = "load_postgres_raw"
    LOAD_QUERY = "load_query"
    LOAD_DELTA = "load_delta"
    OPTIMIZE_DELTA_TABLE = "optimize_delta_table"
    REGISTER_DELTA_TABLE = "register_delta_table"
    SKIP_RUN = "skip_run"
    SYNC_METADATA = "sync_metadata"
