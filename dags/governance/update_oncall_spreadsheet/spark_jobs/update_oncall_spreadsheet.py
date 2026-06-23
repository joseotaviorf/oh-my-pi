"""
Databricks spark job — daily update of on-call hours spreadsheets.

Appends the previous shift's on-call record to the monthly Google Sheet tab
for the AE or DPE squad, depending on the `team` argument ("ae" or "dpe").

Credentials are read from Databricks secrets (scope ``quintoandar``):
  - JIRA_OPS_API: JSON with ``username``, ``token``, ``cloud_id``.
  - GOOGLE_SERVICE_ACCOUNT_CREDENTIALS: GSheets service account JSON key.

Usage::

    python update_oncall_spreadsheet.py ae
    python update_oncall_spreadsheet.py dpe
"""

from __future__ import annotations

import argparse
import json
import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from urllib.parse import quote
from zoneinfo import ZoneInfo

import gspread
import requests
from google.oauth2.service_account import Credentials
from requests.auth import HTTPBasicAuth

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils

logger = logging.getLogger(__name__)

SP_TZ = ZoneInfo("America/Sao_Paulo")
DATABRICKS_SCOPE = "quintoandar"

JIRA_OPS_API_BASE = "https://api.atlassian.com/jsm/ops/api"
JIRA_SERVER = "https://quintoandar.atlassian.net"
GSHEETS_SCOPE = "https://www.googleapis.com/auth/spreadsheets"

# Share each target sheet (Editor permission) with this account before going live.
GSHEETS_SERVICE_ACCOUNT_EMAIL = "gsheets-access@quintoandardata.iam.gserviceaccount.com"

# BRT hours that define the two shift types.
# Normal (Mon–Sat overnight): 21:00 D-1 → 09:00 D.
# Exception (Sun/holiday day shift): 09:00 D-1 → 21:00 D-1.
_SHIFT_HOUR_MORNING = 9
_SHIFT_HOUR_EVENING = 21

_AE_MONTHS = [
    "JAN",
    "FEV",
    "MAR",
    "ABR",
    "MAI",
    "JUN",
    "JUL",
    "AGO",
    "SET",
    "OUT",
    "NOV",
    "DEZ",
]
_DPE_MONTHS = [
    "Jan",
    "Fev",
    "Mar",
    "Apr",
    "Mai",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dez",
]

AE_HEADERS = [
    "DTSTART",
    "DTEND",
    "ATTENDEE",
    "Matrícula",
    "Horas de sobreaviso",
    "Horas de atuacao (seg-sab)",
    "Horas de atuacao noturno (seg-sab)",
    "Horas de atuacao (dom-feriado)",
    "Horas de atuacao noturno (dom-feriado)",
    "Total sobreaviso",
    "Total hora extra",
    "Total de horas a pagar",
]
DPE_HEADERS = [
    "Start",
    "End",
    "On-caller",
    "Registration",
    "On-call hours",
    "Acting hours",
    "Night acting hours (mon-sat)",
    "Acting hours (sun-holiday)",
    "Night acting hours (sun-holiday)",
    "Total on-call hours",
    "Total acting hours",
    "Total payable hours",
]


@dataclass
class TeamConfig:
    """Per-team configuration for on-call spreadsheet updates.

    Encapsulates every team-specific value so that a single ``_update_team``
    function can serve both AE and DPE without branching.
    """

    name: str
    schedule_id: str
    prod_sheet_id: str
    forno_sheet_id: str
    attendees_tab: str
    headers: list[str]
    name_field: str
    registration_field: str
    tab_name_fn: Callable[[datetime], str]
    datetime_format: str
    hours_formula: str
    col_j_formula: str

    def sheet_id(self, environment: str) -> str:
        """Return the correct spreadsheet ID for the given environment."""
        return self.forno_sheet_id if environment == "forno" else self.prod_sheet_id


_AE_CONFIG = TeamConfig(
    name="AE",
    schedule_id="9e63f54a-de9c-4e0d-bf48-75c95a28450d",
    prod_sheet_id="1K5_H_R-EqsVwoacrlEDt3aZ_dawoTQtc-9C0xwAwRkU",
    forno_sheet_id="1B-e6Gm6wMCNTZz3kwGIZbMBdVa7uaqlLh5D_bC-CzT0",
    attendees_tab="Plantonistas",
    headers=AE_HEADERS,
    name_field="Nome",
    registration_field="Matrícula",
    tab_name_fn=lambda dt: f"Horas - {_AE_MONTHS[dt.month - 1]}/{dt.year}",
    datetime_format="%m/%d/%Y %H:%M:00",
    hours_formula="=HOUR(B{n}-A{n})+(MINUTE(B{n}-A{n})/60)",
    col_j_formula="=E{n}/3",
)

_DPE_CONFIG = TeamConfig(
    name="DPE",
    schedule_id="2fe05f0a-46ac-4b1c-8c20-fce1a9e5667b",
    prod_sheet_id="1UGo3qmoIZTOKJImRoOifOKVT721BWrZ_qfJbYIFmE2s",
    forno_sheet_id="1lGIsMUjAbqxnQZH_zwvZez-OCpQUtrsgJtKvfwLGkLw",
    attendees_tab="DPEs",
    headers=DPE_HEADERS,
    name_field="DPE",
    registration_field="Registration",
    tab_name_fn=lambda dt: f"{_DPE_MONTHS[dt.month - 1]}-{dt.year % 100:02d}",
    datetime_format="%m/%d/%Y %H:%M:%S",
    hours_formula="=(B{n}-A{n})*24",
    col_j_formula="=E{n}",
)

_TEAM_CONFIGS: dict[str, TeamConfig] = {"ae": _AE_CONFIG, "dpe": _DPE_CONFIG}


def _parse_rfc3339(datetime_str: str) -> datetime:
    """Parse an RFC 3339 datetime string with or without fractional seconds."""
    try:
        return datetime.strptime(datetime_str, "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        return datetime.strptime(datetime_str, "%Y-%m-%dT%H:%M:%S%z")


def _get_gsheets_client(credentials_dict: dict) -> gspread.Client:
    """Create an authenticated gspread client from a service account credentials dict."""
    creds = Credentials.from_service_account_info(
        credentials_dict, scopes=[GSHEETS_SCOPE]
    )
    return gspread.authorize(creds)


def _get_schedule_timeline(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    shift_date: str,
    schedule_id: str,
    interval: int = 1,
    time_suffix: str = "T21:00:00Z",
) -> dict:
    """Fetch the on-call schedule timeline for a given date from Jira Ops.

    time_suffix controls the UTC start of the query window:
    - ``"T21:00:00Z"`` (default): 18:00 BRT on shift_date, captures 21:00 BRT overnight shifts.
    - ``"T00:00:00Z"``: 21:00 BRT on shift_date-1, captures exception shifts starting at 09:00 BRT.
    """
    url = (
        f"{JIRA_OPS_API_BASE}/{quote(cloud_id, safe='')}/v1/schedules/{quote(schedule_id, safe='')}/timeline"
        f"?expand=base,forwarding,override&interval={interval}&intervalUnit=days"
        f"&date={shift_date}{time_suffix}"
    )
    resp = requests.get(url, headers={"Accept": "application/json"}, auth=jira_ops_auth)
    resp.raise_for_status()
    return resp.json()


def _get_user_display(account_id: str, jira_ops_auth: HTTPBasicAuth) -> dict:
    """Resolve a Jira account ID to display name and email address."""
    if not account_id:
        return {"displayName": "Deleted User", "emailAddress": ""}
    resp = requests.get(
        f"{JIRA_SERVER}/rest/api/2/user",
        params={"accountId": account_id},
        headers={"Accept": "application/json"},
        auth=jira_ops_auth,
    )
    resp.raise_for_status()
    data = resp.json()
    return {
        "displayName": data.get("displayName") or account_id or "Unknown",
        "emailAddress": data.get("emailAddress") or "",
    }


def _get_oncall_period(
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    schedule_id: str,
) -> tuple[datetime, datetime, list[dict]]:
    """Determine the most recently completed on-call shift and its participants.

    For normal days (Mon–Sat nights): shift = D-1 21:00 → D 09:00 BRT.
    For exception days (Sunday/holiday): shift = D-1 09:00 → D-1 21:00 BRT.

    Returns (dtstart, dtend, recipients) where recipients is a list of
    {displayName, emailAddress} dicts, one per on-call person.
    """
    now = datetime.now(tz=SP_TZ)
    yesterday = now - timedelta(days=1)
    shift_date = yesterday.strftime("%Y-%m-%d")
    logger.info("shift_date=%s, schedule_id=%s", shift_date, schedule_id)

    timeline = _get_schedule_timeline(cloud_id, jira_ops_auth, shift_date, schedule_id)
    rotations = timeline.get("finalTimeline", {}).get("rotations", [])
    is_exception = bool(rotations) and len(rotations[0].get("periods", [])) == 1
    logger.info("is_exception=%s", is_exception)

    if is_exception:
        logger.info(
            "Exception day detected on D-1 (%s) — re-fetching with midnight UTC window.",
            shift_date,
        )
        timeline = _get_schedule_timeline(
            cloud_id, jira_ops_auth, shift_date, schedule_id, time_suffix="T00:00:00Z"
        )
        rotations = timeline.get("finalTimeline", {}).get("rotations", [])
        dtstart = yesterday.replace(
            hour=_SHIFT_HOUR_MORNING, minute=0, second=0, microsecond=0
        )
        dtend = yesterday.replace(
            hour=_SHIFT_HOUR_EVENING, minute=0, second=0, microsecond=0
        )
    else:
        dtstart = yesterday.replace(
            hour=_SHIFT_HOUR_EVENING, minute=0, second=0, microsecond=0
        )
        dtend = now.replace(hour=_SHIFT_HOUR_MORNING, minute=0, second=0, microsecond=0)

    expected_start_hour = _SHIFT_HOUR_MORNING if is_exception else _SHIFT_HOUR_EVENING
    recipients: list[dict] = []
    for rotation in rotations:
        rotation_name = rotation.get("name", "")
        for period in rotation.get("periods", []):
            start_dt = _parse_rfc3339(period["startDate"]).astimezone(SP_TZ)
            account_id = (period.get("responder") or {}).get("id")
            user = _get_user_display(account_id, jira_ops_auth)
            logger.info(
                "rotation=%s, responder=%s, hour=%s",
                rotation_name,
                user["displayName"],
                start_dt.hour,
            )
            if start_dt.hour == expected_start_hour:
                recipients.append(user)
                logger.info("→ included")

    return dtstart, dtend, recipients


def _get_attendees(gc: gspread.Client, sheet_id: str, tab_name: str) -> list[dict]:
    """Read all attendee records from the given Google Sheet tab."""
    return gc.open_by_key(sheet_id).worksheet(tab_name).get_all_records()


def _find_attendee(
    email: str,
    attendees: list[dict],
    name_field: str,
    registration_field: str,
    fallback_name: str = "NOT FOUND",
) -> tuple[str, str]:
    """Look up a person in the attendees list by email.

    Returns ``(name, registration)``.  When the email is absent the name falls
    back to ``fallback_name`` (pass the Jira display name to keep rows unique
    even when multiple unmatched responders share the same shift window).
    """
    for attendee in attendees:
        if attendee.get("Email") == email:
            name = str(attendee.get(name_field, "NOT FOUND"))
            registration = str(attendee.get(registration_field, "NOT FOUND"))
            return name, registration
    return fallback_name, "NOT FOUND"


def _pad_month(dt_str: str) -> str:
    """Pad the month digit in a MM/DD/YYYY date string to ensure two-digit comparison."""
    parts = dt_str.split("/")
    if parts:
        parts[0] = parts[0].zfill(2)
    return "/".join(parts)


def _write_oncall_row(
    gc: gspread.Client,
    sheet_id: str,
    month_tab_name: str,
    headers: list[str],
    row_base: list,
    hours_formula: str,
    col_j_formula: str,
) -> bool:
    """Write an on-call entry to the monthly tab.

    Creates the tab with headers if it does not exist yet.
    Skips writing if any existing row already covers the same DTSTART/DTEND/attendee (deduplication).

    ``col_j_formula`` is team-specific: AE uses ``=E{n}/3`` (sobreaviso rule),
    DPE uses ``=E{n}`` (total on-call hours without the 1/3 discount).

    Returns True if written, False if deduplicated.
    """
    workbook = gc.open_by_key(sheet_id)
    try:
        sheet = workbook.worksheet(month_tab_name)
    except gspread.exceptions.WorksheetNotFound:
        sheet = workbook.add_worksheet(title=month_tab_name, rows=100, cols=12)
        sheet.insert_row(values=headers, index=1, value_input_option="USER_ENTERED")

    all_rows = sheet.get("A:C")
    last_line = len(all_rows)
    next_line = last_line + 1

    padded_dtstart = _pad_month(row_base[0])
    padded_dtend = _pad_month(row_base[1])
    for existing_row in all_rows[1:]:  # skip header row
        if (
            len(existing_row) >= 3
            and _pad_month(existing_row[0]) == padded_dtstart
            and _pad_month(existing_row[1]) == padded_dtend
            and existing_row[2] == row_base[2]
        ):
            return False

    full_row = list(row_base) + [
        hours_formula.format(n=next_line),
        None,
        None,
        None,
        None,
        col_j_formula.format(n=next_line),
        f"=F{next_line}*1.5+G{next_line}*1.7+H{next_line}*2+I{next_line}*2.2",
        f"=J{next_line}+K{next_line}",
    ]
    sheet.insert_row(
        values=full_row, index=next_line, value_input_option="USER_ENTERED"
    )
    return True


def _update_team(
    config: TeamConfig,
    gc: gspread.Client,
    cloud_id: str,
    jira_ops_auth: HTTPBasicAuth,
    environment: str,
) -> None:
    """Write the previous on-call shift entry for the given team's Google Spreadsheet."""
    dtstart, dtend, recipients = _get_oncall_period(
        cloud_id, jira_ops_auth, config.schedule_id
    )
    if not recipients:
        logger.warning(
            "No on-call recipients found for %s schedule — skipping.", config.name
        )
        return

    sheet_id = config.sheet_id(environment)
    attendees = _get_attendees(gc, sheet_id, config.attendees_tab)
    month_tab = config.tab_name_fn(dtstart)
    dtstart_str = dtstart.strftime(config.datetime_format)
    dtend_str = dtend.strftime(config.datetime_format)

    for recipient in recipients:
        name, registration = _find_attendee(
            recipient["emailAddress"],
            attendees,
            config.name_field,
            config.registration_field,
            fallback_name=recipient["displayName"],
        )
        row_base = [dtstart_str, dtend_str, name, registration]
        written = _write_oncall_row(
            gc,
            sheet_id,
            month_tab,
            config.headers,
            row_base,
            config.hours_formula,
            config.col_j_formula,
        )
        if written:
            logger.info(
                "Wrote %s on-call row for %s (%s → %s)",
                config.name,
                recipient["displayName"],
                dtstart_str,
                dtend_str,
            )
        else:
            logger.info(
                "Skipped %s — entry already exists for %s → %s",
                config.name,
                dtstart_str,
                dtend_str,
            )


def main() -> None:
    """Entry point: parse arguments, read secrets, and dispatch to the correct update function."""
    parser = argparse.ArgumentParser(
        description="Update on-call hours spreadsheet for a given team."
    )
    parser.add_argument(
        "team",
        choices=list(_TEAM_CONFIGS),
        help="Squad whose spreadsheet should be updated.",
    )
    parser.add_argument(
        "environment",
        choices=["forno", "prod"],
        help="Execution environment — selects the correct target spreadsheet.",
    )
    args = parser.parse_args()

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    jira_ops_secret = json.loads(
        dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.JIRA_OPS)
    )
    cloud_id = jira_ops_secret["cloud_id"]
    jira_ops_auth = HTTPBasicAuth(jira_ops_secret["username"], jira_ops_secret["token"])

    gsheets_credentials = json.loads(
        dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.GSHEETS_CREDENTIALS)
    )
    gc = _get_gsheets_client(gsheets_credentials)

    _update_team(
        _TEAM_CONFIGS[args.team], gc, cloud_id, jira_ops_auth, args.environment
    )


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
