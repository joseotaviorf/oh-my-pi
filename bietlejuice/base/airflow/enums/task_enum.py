from enum import Enum


class TaskEnum(Enum):
    DATA_QUALITY_TESTS = "data_quality_tests"
    DUMMY_JOB_CLUSTER_FINISHED = "dummy_job_cluster_finished"
    EXECUTE_JOB_CLUSTER = "execute_job_cluster"
    LOAD_CDC_CLEAN = "load_cdc_clean"
    LOAD_CDC_RAW = "load_cdc_raw"
    LOAD_CDC_TRANSACTIONAL = "load_cdc_transactional"
    LOAD_MONGO_RAW = "load_mongo_raw"
    LOAD_POSTGRES_RAW = "load_postgres_raw"
    LOAD_QUERY = "load_query"
    PROPAGATE_METADATA = "propagate_metadata"
    SYNC_HIVE_PARTITIONS = "sync_hive_partitions"
    SYNC_HIVE_STRUCTURE = "sync_hive_structure"
