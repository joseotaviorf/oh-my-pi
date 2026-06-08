from datetime import datetime, timezone
from typing import Any, Dict, Optional

import requests


def get_response_metadata(response: requests.Response, error=None):
    return {
        "request_timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "method": response.request.method,
        "url": response.request.url,
        "final_url": response.url,
        "status_code": response.status_code,
        "success": response.ok,
        "error": error,
        "elapsed_seconds": response.elapsed.total_seconds(),
        "response_size_bytes": len(response.content),
        "content_type": response.headers.get("Content-Type"),
        "redirected": bool(response.history),
        "redirect_count": len(response.history),
    }


def post_request(
    endpoint: str,
    payload: Dict[str, Any] = None,
    headers: Optional[Dict[str, str]] = None,
    timeout: int = 30,
    return_logs: bool = False,
) -> Dict[str, Any]:
    try:
        response = requests.post(
            url=endpoint,
            data=payload,
            headers=headers,
            timeout=timeout,
        )

        response.raise_for_status()
        if return_logs:
            logs = get_response_metadata(response)
            return response.json(), logs
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
    return_logs: bool = False,
) -> Dict[str, Any]:
    try:
        response = requests.get(
            endpoint,
            params=params,
            headers=headers,
            timeout=timeout,
        )

        response.raise_for_status()
        if return_logs:
            logs = get_response_metadata(response)
            return response.json(), logs
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
