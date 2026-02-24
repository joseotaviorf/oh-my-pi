from enum import Enum


class AuthenticationStrategyEnum(Enum):
    """
    Authentication strategies supported by the API Ingestion workflow.
    """

    OAUTH2_CLIENT_CREDENTIALS = "oauth2_client_credentials"
    BASIC = "basic"
    API_KEY = "api_key"
    NONE = "none"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]


class PaginationStrategyEnum(Enum):
    """
    Pagination strategies supported by the API Ingestion workflow.
    """

    CURSOR = "cursor"
    OFFSET_LIMIT = "offset_limit"
    NONE = "none"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]


class RateLimitingStrategyEnum(Enum):
    """
    Rate limiting strategies supported by the API Ingestion workflow.
    """

    FIXED_DELAY = "fixed_delay"
    NONE = "none"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
