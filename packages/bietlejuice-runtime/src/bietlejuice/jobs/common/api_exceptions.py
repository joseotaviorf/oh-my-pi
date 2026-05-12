import requests


class APIException(Exception):
    """
    Base class for exceptions related to API calls.
    It captures the message, status code, and response body for
    more detailed logging.
    """

    def __init__(
        self, message="An API error occurred", status_code=None, response_text=None
    ):
        self.status_code = status_code
        self.response_text = response_text

        details = []
        if status_code:
            details.append(f"Status Code: {status_code}")
        if response_text:
            # Show only the first 300 characters to avoid flooding the logs
            details.append(f"Response Body: {response_text[:300]}")

        details_str = ". ".join(details)
        super().__init__(f"{message}. {details_str}")


class BadRequestError(APIException):
    """Exception for 400 Bad Request errors."""

    def __init__(self, message="Bad Request", response_text=None):
        super().__init__(message, status_code=400, response_text=response_text)


class UnauthorizedError(APIException):
    """Exception for 401 Unauthorized errors."""

    def __init__(
        self, message="Unauthorized. Please check API credentials", response_text=None
    ):
        super().__init__(message, status_code=401, response_text=response_text)


class ForbiddenError(APIException):
    """Exception for 403 Forbidden errors."""

    def __init__(
        self, message="Forbidden. Please check permissions", response_text=None
    ):
        super().__init__(message, status_code=403, response_text=response_text)


class NotFoundError(APIException):
    """Exception for 404 Not Found errors."""

    def __init__(self, message="Resource not found", response_text=None):
        super().__init__(message, status_code=404, response_text=response_text)


class RateLimitError(APIException):
    """Exception for 429 Too Many Requests errors."""

    def __init__(self, message="API rate limit exceeded", response_text=None):
        super().__init__(message, status_code=429, response_text=response_text)


class InternalServerError(APIException):
    """Exception for 5xx server-side errors."""

    def __init__(
        self, message="Internal Server Error", status_code=500, response_text=None
    ):
        super().__init__(message, status_code=status_code, response_text=response_text)


def raise_for_status(response: requests.Response):
    """
    Analyzes the response from a request and raises a custom API exception
    in case of an error.

    Args:
        response (requests.Response): The response object from the request.
    """
    if not response.ok:
        status_code = response.status_code
        response_text = response.text

        if status_code == 400:
            raise BadRequestError(response_text=response_text)
        elif status_code == 401:
            raise UnauthorizedError(response_text=response_text)
        elif status_code == 403:
            raise ForbiddenError(response_text=response_text)
        elif status_code == 404:
            raise NotFoundError(response_text=response_text)
        elif status_code == 429:
            raise RateLimitError(response_text=response_text)
        elif 500 <= status_code < 600:
            raise InternalServerError(
                status_code=status_code, response_text=response_text
            )
        else:
            # General exception for other client-side errors (4xx)
            raise APIException(
                message="Unhandled client error",
                status_code=status_code,
                response_text=response_text,
            )
