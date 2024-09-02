class DatabricksGroupNameEnum:
    """
    Mapping of all groups in Databricks for defining permissions to clusters.
    """

    # Default Databricks Groups
    ADMINS = "admins"
    ALL_USERS = "users"

    # QuintoAndar custom groups
    ANALYTICS_ENGINEERS = "analytics-engineers"
    DATA_ANALYTICS = "analytics"
    DATA_PLATFORM_ENGINEERS = "data-platform-engineers"
    DATA_PRODUCTS = "data-products"
    SOFTWARE_ENGINEERS = "software-engineers"
    BUSINESS_ANALYSTS_CREDIT = "credit-team"
    MLOPS = "mlops"
    PEOPLE_ANALYTICS = "people-analytics"
    ANALYTICAL_ENVIRONMENT_COSTS = "analytical-environment-costs"

    @classmethod
    def get_available_enum_values(cls):
        return [
            v
            for k, v in cls.__dict__.items()
            if not k.startswith("_") and isinstance(v, str)
        ]
