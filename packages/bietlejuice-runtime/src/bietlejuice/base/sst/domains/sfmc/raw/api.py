import base64
import binascii
import json
from typing import Any, Dict, List

import requests
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils

logger = QuintoAndarLogger("sst.domains.sfmc.api")


def _parse_secret_json(raw: str) -> Any:
    payload = (raw or "").strip()
    if not payload:
        raise ValueError("SFMC credentials secret is empty")
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        pass
    try:
        decoded = base64.b64decode(payload, validate=True).decode("utf-8")
        return json.loads(decoded)
    except (
        binascii.Error,
        ValueError,
        UnicodeDecodeError,
        json.JSONDecodeError,
    ) as exc:
        raise ValueError(
            "Invalid SFMC credentials secret format. Expected JSON object."
        ) from exc


def derive_soap_url(rest_url: str, auth_url: str) -> str:
    if rest_url and ".rest." in rest_url:
        return rest_url.replace(".rest.", ".soap.", 1)
    if auth_url and ".auth." in auth_url:
        return auth_url.replace(".auth.", ".soap.", 1)
    raise ValueError(
        "Could not derive SFMC soap_url from credentials. "
        "Set soap_url in secret or provide auth_url/rest_url with known SFMC host format."
    )


def get_api_credentials() -> Dict[str, str]:
    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    if dbutils is None:
        raise ValueError(
            "Databricks dbutils is not available to retrieve SFMC secrets."
        )

    api_credentials = _parse_secret_json(
        dbutils.secrets.get(scope="quintoandar", key=APIEnum.SFMC)
    )
    if not isinstance(api_credentials, dict):
        raise ValueError(
            "Invalid SFMC credentials secret format. Expected JSON object."
        )

    return {
        "client_id": str(api_credentials.get("client_id", "")).strip(),
        "client_secret": str(api_credentials.get("client_secret", "")).strip(),
        "auth_url": str(api_credentials.get("auth_url", "")).strip(),
        "rest_url": str(api_credentials.get("rest_url", "")).strip(),
        "soap_url": str(api_credentials.get("soap_url", "")).strip(),
    }


def resolve_api_credentials(
    require_rest_url: bool = False,
    require_soap_url: bool = False,
) -> Dict[str, str]:
    credentials = get_api_credentials()

    client_id = credentials["client_id"]
    client_secret = credentials["client_secret"]
    auth_url = credentials["auth_url"]
    rest_url = credentials["rest_url"]
    soap_url = credentials["soap_url"]

    if not client_id or not client_secret:
        raise ValueError(
            "SFMC credentials secret must include client_id and client_secret."
        )
    if not auth_url:
        raise ValueError("SFMC credentials secret must include auth_url.")
    if require_rest_url and not rest_url:
        raise ValueError("SFMC credentials secret must include rest_url.")
    if require_soap_url and not soap_url:
        soap_url = derive_soap_url(rest_url=rest_url, auth_url=auth_url)
    if require_soap_url and not soap_url:
        raise ValueError("SFMC credentials secret must include soap_url.")

    return {
        "client_id": client_id,
        "client_secret": client_secret,
        "auth_url": auth_url,
        "rest_url": rest_url,
        "soap_url": soap_url,
    }


@logger(exclude=["client_id", "client_secret"], exclude_return=True)
def get_access_token(
    auth_url: str,
    client_id: str,
    client_secret: str,
) -> str:
    token_url = f"{auth_url.rstrip('/')}/v2/token"
    payload = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    }
    response = requests.post(
        token_url,
        headers={"Content-Type": "application/json"},
        json=payload,
        timeout=60,
    )
    response.raise_for_status()
    access_token = response.json().get("access_token")
    if not access_token:
        raise ValueError("SFMC access token not found in auth response.")
    return access_token


@logger(exclude=["access_token"], exclude_return=True)
def fetch_object_rows(
    rest_url: str,
    access_token: str,
    external_key: str,
    page_size: int = 2500,
) -> List[Dict[str, Any]]:
    data_url = (
        f"{rest_url.rstrip('/')}/data/v1/customobjectdata/key/{external_key}/rowset"
    )
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    all_rows: List[Dict[str, Any]] = []

    def _fetch_page(page: int) -> None:
        response = requests.get(
            data_url,
            headers=headers,
            params={"$page": page, "$pageSize": page_size},
            timeout=120,
        )
        response.raise_for_status()
        response_json = response.json()

        if isinstance(response_json, list):
            page_rows = response_json
        elif isinstance(response_json, dict) and isinstance(
            response_json.get("items"), list
        ):
            page_rows = response_json.get("items", [])
        elif isinstance(response_json, dict) and isinstance(
            response_json.get("rowset"), list
        ):
            page_rows = response_json.get("rowset", [])
        else:
            page_rows = []

        logger.info(
            "m=fetch_object_rows, "
            f"msg=Fetched page for data extension, page={page}, rows_count={len(page_rows)}"
        )

        if not page_rows:
            return

        all_rows.extend(page_rows)

        if len(page_rows) < page_size:
            return

        _fetch_page(page + 1)

    _fetch_page(page=1)

    logger.info(
        "m=fetch_object_rows, "
        f"msg=Finished pagination for external_key={external_key}, total_rows={len(all_rows)}"
    )
    return all_rows
