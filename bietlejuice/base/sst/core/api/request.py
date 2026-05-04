from typing import Any, Dict, Optional
import requests


def post_request(
    endpoint: str,
    payload: Dict[str, Any] = None,
    headers: Optional[Dict[str, str]] = None,
    timeout: int = 30,
) -> Dict[str, Any]:
    try:
        response = requests.post(
            url=endpoint,
            data=payload,
            headers=headers,
            timeout=timeout,
        )

        response.raise_for_status()

        return response.json()

    except requests.exceptions.HTTPError as error:
        raise RuntimeError(
            f"POST request failed with status {response.status_code}: {response.text}"
        ) from error

    except requests.exceptions.Timeout as error:
        raise RuntimeError("POST request timed out") from error

    except requests.exceptions.RequestException as error:
        raise RuntimeError(f"POST request failed: {error}") from error

    except ValueError as error:
        raise RuntimeError(f"Response is not valid JSON: {response.text}") from error


def get_request(
    endpoint: str,
    params: Optional[Dict[str, Any]] = None,
    headers: Optional[Dict[str, str]] = None,
    timeout: int = 30,
) -> Dict[str, Any]:
    try:
        response = requests.get(
            endpoint,
            params=params,
            headers=headers,
            timeout=timeout,
        )

        response.raise_for_status()
        return response.json()

    except requests.exceptions.HTTPError as error:
        raise RuntimeError(
            f"GET request failed with status {response.status_code}: {response.text}"
        ) from error

    except requests.exceptions.Timeout as error:
        raise RuntimeError("GET request timed out") from error

    except requests.exceptions.RequestException as error:
        raise RuntimeError(f"GET request failed: {error}") from error

    except ValueError as error:
        raise RuntimeError(f"Response is not valid JSON: {response.text}") from error
