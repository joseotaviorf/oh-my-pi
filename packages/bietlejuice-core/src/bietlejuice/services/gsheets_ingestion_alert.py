"""Helpers to classify Google Sheets ingestion failures and format GChat alerts."""

from __future__ import annotations

import re
from dataclasses import dataclass
from os import path
from typing import Any, Dict, Optional, Tuple

import yaml

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService

MSG_HEADER = (
    "⚠️ *Gsheet ingestion failures*\n"
    "The following sheet was not ingested in this run due to some error.\n"
)

_UNRESOLVED_COLUMN_RE = re.compile(
    r"name\s+[`'\"]?(\w+)[`'\"]?\s+cannot be resolved",
    re.IGNORECASE,
)

_DID_YOU_MEAN_RE = re.compile(
    r"did you mean one of the following\?\s*\[([^\]]+)\]",
    re.IGNORECASE,
)

ERROR_TYPE_DISPLAY_LABELS = {
    "SCHEMA_DRIFT": "Missing or renamed column",
    "EMPTY_SHEET": "Empty sheet tab",
    "SPREADSHEET_NOT_FOUND": "Spreadsheet not found or inaccessible",
    "WORKSHEET_NOT_FOUND": "Sheet tab not found",
    "PERMISSION": "No permission to read the sheet",
    "OTHER": "Unexpected error",
}


@dataclass(frozen=True)
class GsheetIngestionErrorInfo:
    error_type: str
    likely_cause: str


def display_error_type(error_type: str) -> str:
    """Map internal error codes to plain-English labels for GChat alerts."""
    return ERROR_TYPE_DISPLAY_LABELS.get(error_type, error_type)


def _extract_column_suggestions(message: str) -> Tuple[Optional[str], Optional[str]]:
    """Return (missing_column, suggestion_list) from Spark UNRESOLVED_COLUMN errors."""
    unresolved = _UNRESOLVED_COLUMN_RE.search(message)
    missing_column = unresolved.group(1) if unresolved else None

    suggestion_match = _DID_YOU_MEAN_RE.search(message)
    suggestions = suggestion_match.group(1).strip() if suggestion_match else None

    return missing_column, suggestions


def _build_schema_drift_likely_cause(
    missing_column: str, suggestions: Optional[str]
) -> str:
    cause = (
        f"The clean SQL expects column '{missing_column}', but it is missing from "
        "the sheet header (renamed or removed)."
    )
    if suggestions:
        cause += f" Did you mean: {suggestions}?"
    return cause


def classify_gsheet_ingestion_error(
    exception: BaseException,
) -> GsheetIngestionErrorInfo:
    """Map a raw exception to a stable Type + Likely cause for on-call alerts."""
    message = str(exception)
    first_line = message.split("\n")[0]
    lower = message.lower()

    if "empty!" in lower or "__generate_schema" in lower:
        return GsheetIngestionErrorInfo(
            error_type="EMPTY_SHEET",
            likely_cause=(
                "The tab returned 0 rows. It may be truly empty, or an "
                "IMPORTRANGE that has not resolved / lacks permission for the "
                "service account."
            ),
        )

    if (
        "not_found" in lower
        or "requested entity was not found" in lower
        or "'code': 404" in lower
        or '"code": 404' in lower
    ):
        return GsheetIngestionErrorInfo(
            error_type="SPREADSHEET_NOT_FOUND",
            likely_cause=(
                "Spreadsheet ID is invalid, the file was deleted, or the "
                "service account cannot access it."
            ),
        )

    if "worksheetnotfound" in lower or "worksheet not found" in lower:
        return GsheetIngestionErrorInfo(
            error_type="WORKSHEET_NOT_FOUND",
            likely_cause=(
                "The configured sheet_name does not match any tab in the "
                "spreadsheet (check prod_conf vs the Google Sheet tab name)."
            ),
        )

    missing_column, suggestions = _extract_column_suggestions(message)
    if missing_column or "unresolved_column" in lower:
        column_label = missing_column or "unknown"
        return GsheetIngestionErrorInfo(
            error_type="SCHEMA_DRIFT",
            likely_cause=_build_schema_drift_likely_cause(column_label, suggestions),
        )

    if "permission" in lower or "403" in first_line:
        return GsheetIngestionErrorInfo(
            error_type="PERMISSION",
            likely_cause=(
                "The service account does not have permission to read this "
                "spreadsheet. Share the file with the Google Sheets SA."
            ),
        )

    # gspread often raises WorksheetNotFound with only the tab name as message.
    # When the first line is a short bare token (no spaces / structured error),
    # treat it as a missing tab name.
    stripped = first_line.strip().strip("'\"")
    if stripped and " " not in stripped and len(stripped) <= 80 and "=" not in stripped:
        return GsheetIngestionErrorInfo(
            error_type="WORKSHEET_NOT_FOUND",
            likely_cause=(
                f"The configured sheet_name '{stripped}' was not found as a tab "
                "in the spreadsheet (check prod_conf vs the Google Sheet tab name)."
            ),
        )

    return GsheetIngestionErrorInfo(
        error_type="OTHER",
        likely_cause="Unexpected ingestion error. Inspect the Error details below.",
    )


def _truncate_at_word(text: str, max_length: int) -> str:
    text = text.strip()
    if len(text) <= max_length:
        return text
    truncated = text[: max_length - 3].rstrip()
    last_space = truncated.rfind(" ")
    if last_space > max_length // 2:
        truncated = truncated[:last_space]
    return truncated + "..."


def sanitize_error_trace(exception: BaseException, max_length: int = 400) -> str:
    """First exception line, scrubbed for GChat code fences, truncated."""
    error_trace = str(exception).split("\n")[0]
    for bad_char in ["`", '"']:
        error_trace = error_trace.replace(bad_char, "")
    return _truncate_at_word(error_trace, max_length)


def format_error_for_alert(
    exception: BaseException,
    error_info: GsheetIngestionErrorInfo,
) -> str:
    """Prefer a structured summary for schema drift; otherwise sanitize raw trace."""
    message = str(exception)
    if error_info.error_type == "SCHEMA_DRIFT":
        missing_column, suggestions = _extract_column_suggestions(message)
        if missing_column:
            summary = (
                f"UNRESOLVED_COLUMN: column '{missing_column}' cannot be resolved."
            )
            if suggestions:
                summary += f" Did you mean [{suggestions}]?"
            return summary
    return sanitize_error_trace(exception)


def get_metadata_owner(
    dag_name: str, table_name: str, layer: str = "clean"
) -> Optional[str]:
    """
    Best-effort owner from ``metadata/{layer}/{table}.yml`` when the DAG package
    is available on the local filesystem (Composer / local).

    Metadata files are not shipped in the Spark queries/spark_jobs/data_quality
    artifact, so Databricks jobs usually cannot resolve this unless Airflow
    injected ``owner`` into ``sheet_details``.
    """
    dag_path = DAGPackagesPathService.get_dag_path(dag_name)
    if not dag_path:
        return None

    for extension in ("yml", "yaml"):
        metadata_path = path.join(
            dag_path, "metadata", layer, f"{table_name}.{extension}"
        )
        if not path.isfile(metadata_path):
            continue
        try:
            with open(metadata_path, encoding="utf-8") as metadata_file:
                payload = yaml.safe_load(metadata_file) or {}
        except (OSError, yaml.YAMLError):
            return None
        owner = payload.get("owner")
        if isinstance(owner, str) and owner.strip():
            return owner.strip()
    return None


def resolve_alert_owner(
    sheet_details: Dict[str, Any], dag_name: Optional[str] = None
) -> Optional[str]:
    """Prefer owner already on sheet_details; otherwise try metadata on disk."""
    owner = sheet_details.get("owner")
    if isinstance(owner, str) and owner.strip():
        return owner.strip()

    clean_table_name = sheet_details.get("clean_table_name")
    if dag_name and clean_table_name:
        return get_metadata_owner(dag_name, clean_table_name)
    return None


def format_gsheet_ingestion_alert(
    sheet_details: Dict[str, Any],
    exception: BaseException,
    dag_name: Optional[str] = None,
) -> str:
    """Build the GChat alert body, preserving the historical layout."""
    error_info = classify_gsheet_ingestion_error(exception)
    error_trace = format_error_for_alert(exception, error_info)
    sheet_url = f"https://docs.google.com/spreadsheets/d/{sheet_details['sheet_id']}"
    owner = resolve_alert_owner(sheet_details, dag_name=dag_name)

    lines = [
        f"\n🎲 *Sheet*: <{sheet_url}|{sheet_details['clean_table_name']}> "
        f"(ID: {sheet_details['sheet_id']})",
        f"*Owner Team*: {sheet_details['sheet_context']}.",
    ]
    if owner:
        lines.append(f"*Data Owner*: {owner}")
    lines.extend(
        [
            f"*Type*: {display_error_type(error_info.error_type)}",
            f"*Likely cause*: {error_info.likely_cause}",
            f"*❌ Error*: ```{error_trace}```",
        ]
    )
    return MSG_HEADER + "\n".join(lines)
