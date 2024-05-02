from enum import Enum


class WorkflowEnum(Enum):
    """
    Mapping of bi-etl-ejuice workflow types to an Enum object.
    """

    CDC_WORKFLOW = "cdc"
    DATABASE_PULL_WORKFLOW = "database_pull"
    CUSTOM_INGESTION_WORKFLOW = "custom_ingestion"
    GSHEETS_WORKFLOW = "gsheets"
    QUERY_WORKFLOW = "query"
    QUERY_DELTA_WORKFLOW = "query_delta"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
