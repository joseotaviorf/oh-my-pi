from enum import Enum


class WorkflowEnum(Enum):
    """
    Mapping of bi-etl-ejuice workflow types to an Enum object.
    """

    QUERY_WORKFLOW = "query"
    GSHEETS_WORKFLOW = "gsheets"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
