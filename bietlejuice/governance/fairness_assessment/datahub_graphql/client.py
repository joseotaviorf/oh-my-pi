"""DataHub GraphQL client: URL resolution, HTTP POST, and response JSON parsing (F4, I1-02, I3)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any, Iterator, Mapping, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_DATA_CONTRACT_URN_MARKER,
    DATAHUB_FETCH_ERROR,
    DATAHUB_HTTP_ERROR,
    DATAHUB_URN_DIAG_OK,
)

LOGGER = QuintoAndarLogger(__name__)

# Truncate response bodies in logs to avoid leaking large payloads / dumping noise; 500 chars is
# enough for typical GraphQL/Auth error envelopes (HTML 401, JSON ``errors`` array, etc.).
_HTTP_ERROR_BODY_MAX_CHARS = 500

# -- URL + HTTP ----------------------------------------------------------------


def resolve_datahub_graphql_url(config_service: Any) -> str:
    """GraphQL endpoint for DataHub (``POST`` with ``query`` / ``variables``).

    Resolution order:

    1. ``DATAHUB_GRAPHQL_URL`` — full URL (e.g. ``https://datahub.../api/graphql``).
    2. ``datahub_graphql_url`` from merged env YAML (``forno_conf.yml`` / ``prod_conf.yml``).
    3. ``{datahub_host}/api/graphql`` when ``datahub_host`` is set.
    """

    env = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
    if env:
        return env.rstrip("/")
    explicit = str(config_service.configs.get("datahub_graphql_url") or "").strip()
    if explicit:
        return explicit.rstrip("/")
    host = str(config_service.configs.get("datahub_host") or "").strip().rstrip("/")
    if host:
        return f"{host}/api/graphql"
    return ""


def resolve_datahub_gms_base_url(config_service: Any) -> str:
    """Deprecated alias: GMS host URL. Prefer ``resolve_datahub_graphql_url`` for fairness checks."""

    env = os.environ.get("DATAHUB_GMS_HOST", "").strip()
    if env:
        return env
    return str(config_service.configs.get("datahub_gms_host") or "").strip()


def datahub_graphql_post(
    graphql_url: str,
    token: Optional[str],
    query: str,
    variables: Mapping[str, Any],
    timeout_sec: float = 60.0,
) -> tuple[Optional[dict[str, Any]], str]:
    """POST GraphQL body; returns (parsed JSON root dict or None, diagnostic).

    HTTP 200 can still contain GraphQL ``errors``; see DataHub docs.
    """

    payload = json.dumps({"query": query, "variables": dict(variables)}).encode("utf-8")
    req = urllib.request.Request(
        graphql_url,
        data=payload,
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            status = int(getattr(resp, "status", None) or resp.getcode())
            if status != 200:
                LOGGER.warning(
                    f"m=datahub_graphql_post_non_200,url={graphql_url},status={status}"
                )
                return None, DATAHUB_HTTP_ERROR
            raw = resp.read()
            if not raw or not raw.strip():
                LOGGER.warning(
                    f"m=datahub_graphql_post_empty_body,url={graphql_url},status={status}"
                )
                return None, DATAHUB_FETCH_ERROR
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                LOGGER.warning(f"m=datahub_graphql_post_decode_error,url={graphql_url}")
                return None, DATAHUB_FETCH_ERROR
            try:
                root = json.loads(text)
            except json.JSONDecodeError:
                LOGGER.warning(
                    f"m=datahub_graphql_post_json_error,url={graphql_url},"
                    f"body={text[:_HTTP_ERROR_BODY_MAX_CHARS]}"
                )
                return None, DATAHUB_FETCH_ERROR
            return root, DATAHUB_URN_DIAG_OK
    except urllib.error.HTTPError as exc:
        body = ""
        try:
            body = exc.read().decode("utf-8", errors="replace")[
                :_HTTP_ERROR_BODY_MAX_CHARS
            ]
        except Exception:
            # Body may already be consumed or unreadable; status/reason are still actionable.
            pass
        LOGGER.warning(
            f"m=datahub_graphql_post_http_error,url={graphql_url},"
            f"status={exc.code},reason={exc.reason},body={body}"
        )
        return None, DATAHUB_HTTP_ERROR
    except TimeoutError as exc:
        LOGGER.warning(
            f"m=datahub_graphql_post_timeout,url={graphql_url},"
            f"timeout_sec={timeout_sec},err={exc}"
        )
        return None, DATAHUB_FETCH_ERROR
    except urllib.error.URLError as exc:
        LOGGER.warning(
            f"m=datahub_graphql_post_url_error,url={graphql_url},reason={exc.reason}"
        )
        return None, DATAHUB_FETCH_ERROR
    except OSError as exc:
        LOGGER.warning(f"m=datahub_graphql_post_os_error,url={graphql_url},err={exc}")
        return None, DATAHUB_FETCH_ERROR


# -- GraphQL / entity JSON parsing ----------------------------------------------------------------


def _iter_json_strings(obj: Any) -> Iterator[str]:
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _iter_json_strings(v)
    elif isinstance(obj, list):
        for x in obj:
            yield from _iter_json_strings(x)


def entity_json_has_data_contract_resource(entity_payload: Any) -> bool:
    """True if the Databricks entity payload contains an **assigned** data contract resource."""

    for s in _iter_json_strings(entity_payload):
        if isinstance(s, str) and DATAHUB_DATA_CONTRACT_URN_MARKER in s:
            return True
    return False


def institutional_memory_has_assigned_datacontract(institutional_memory: Any) -> bool:
    """True if any ``institutionalMemory.elements[].label`` contains a datacontract URN assignment."""

    if not isinstance(institutional_memory, dict):
        return False
    elements = institutional_memory.get("elements")
    if not isinstance(elements, list):
        return False
    for el in elements:
        if not isinstance(el, dict):
            continue
        label = el.get("label")
        if not isinstance(label, str):
            continue
        if "No data contract assigned" in label:
            continue
        if DATAHUB_DATA_CONTRACT_URN_MARKER in label:
            return True
    return False


def _parse_dataset_fair_signals(
    root: Mapping[str, Any],
) -> tuple[
    bool,
    bool,
    bool,
    int,
    int,
    bool,
]:
    """From GraphQL root JSON, return (indexed_ok, has_contract, ownership_nonempty, up_tot, down_tot, had_dataset)."""

    data = root.get("data")
    if not isinstance(data, dict):
        return False, False, False, 0, 0, False
    ds = data.get("dataset")
    if ds is None:
        return False, False, False, 0, 0, False
    if not isinstance(ds, dict):
        return False, False, False, 0, 0, False

    exists = ds.get("exists")
    indexed_ok = bool(exists) if exists is not None else False

    inst = ds.get("institutionalMemory")
    has_contract = institutional_memory_has_assigned_datacontract(inst)

    owners_block = ds.get("ownership") if isinstance(ds.get("ownership"), dict) else {}
    owners_list = owners_block.get("owners") if isinstance(owners_block, dict) else None
    ownership_nonempty = bool(isinstance(owners_list, list) and len(owners_list) > 0)

    up_obj = ds.get("upstream") if isinstance(ds.get("upstream"), dict) else {}
    down_obj = ds.get("downstream") if isinstance(ds.get("downstream"), dict) else {}
    up_tot = up_obj.get("total")
    down_tot = down_obj.get("total")
    try:
        up_n = int(up_tot) if up_tot is not None else 0
    except (TypeError, ValueError):
        up_n = 0
    try:
        down_n = int(down_tot) if down_tot is not None else 0
    except (TypeError, ValueError):
        down_n = 0

    return indexed_ok, has_contract, ownership_nonempty, up_n, down_n, True
