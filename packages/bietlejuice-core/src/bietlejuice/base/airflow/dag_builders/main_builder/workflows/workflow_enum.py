from enum import Enum


class WorkflowEnum(Enum):
    """
    Mapping of bi-etl-ejuice workflow types to an Enum object.
    """

    ACCESS_WORKFLOW = "access"
    API_INGESTION_WORKFLOW = "api_ingestion"
    CDC_WORKFLOW = "cdc"
    CORE_MODEL_WORKFLOW = "core_model"
    CUSTOM_INGESTION_WORKFLOW = "custom_ingestion"
    DATABASE_PULL_DELTA_WORKFLOW = "database_pull_delta"
    DATABASE_PULL_WORKFLOW = "database_pull"
    DMS_CDC_WORKFLOW = "dms_cdc"
    GSHEETS_WORKFLOW = "gsheets"
    LOAD_ACCESS_WORKFLOW = "load_access"
    LOAD_WORKFLOW = "load"
    QUERY_DELTA_WORKFLOW = "query_delta"
    QUERY_WORKFLOW = "query"
    QUERY_VIEW_WORKFLOW = "query_view"
    QUBE_DIMENSION_WORKFLOW = "qube_dimension"
    QUBE_MEASURE_WORKFLOW = "qube_measure"
    QUBE_METRIC_WORKFLOW = "qube_metric"
    WONKA_WORKFLOW = "wonka"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
