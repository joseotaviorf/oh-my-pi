from enum import Enum


class DatabricksGroupNameEnum(Enum):
    """
    Mapping of all groups in Databricks for defining permissions to clusters.
    """

    # Default Databricks Groups
    ADMINS = "admins"
    ALL_USERS = "users"

    # QuintoAndar custom groups
    ANALYTICS_ENGINEERS = "analytics-engineers"
    DATA_ANALYTICS = "analytics"
    DATA_PRODUCTS = "data-products"
    SOFTWARE_ENGINEERS = "software-engineers"
    BUSINESS_ANALYSTS_CREDIT = "credit-team"
    MLOPS = "mlops"
    PEOPLE_ANALYTICS = "people-analytics"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
