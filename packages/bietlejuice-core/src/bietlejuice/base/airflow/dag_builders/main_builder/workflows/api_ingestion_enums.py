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
    PAGE_PER_PAGE = "page_per_page"
    NONE = "none"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]


class HttpMethodEnum(Enum):
    """
    HTTP methods a table can use for its data requests in the API Ingestion workflow.
    """

    GET = "get"
    POST = "post"

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
