from requests.adapters import HTTPAdapter


class BaseRateLimitAdapter(HTTPAdapter):
    """
    Base class for different rate limit control strategies.

    It inherits from HTTPAdapter so that subclasses can be mounted directly
    onto a `requests` session.
    """

    pass
