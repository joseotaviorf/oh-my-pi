"""DM the DEI incident org hierarchy when a card is stuck too long — no Jira
Automation, no Jira custom fields. (See PR #28669: Jira Cloud's outbound
"Send web request" can't reach NHI's internal-only `/webhook/generic` route,
so this job calls it directly; and since nothing reads a Jira field for
this, identity lives only in this job's resolution and the Jira escalation-notified
property.)

Full design rationale is documented in the DAG declaration's dag_purpose and
PR #28669 — kept out of this docstring so `from __future__ import
annotations` stays within validate-py39-runtime-typing's scan window.

Escalation day thresholds scale with the issue's Criticality field — see
EscalationPolicy. Idempotent via the "escalation-notified" Issue Property
(last level DMed).
"""

from __future__ import annotations

import html
import json
from argparse import ArgumentParser, Namespace
from datetime import datetime, timezone
from functools import cache

import requests
import yaml
from quintoandar_logger import QuintoAndarLogger
from requests.auth import HTTPBasicAuth

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient

JOB_NAME = "sync_escalation_hierarchy"
DEI_PROJECT_ID = "11446"
JIRA_SERVER = "https://quintoandar.atlassian.net"
DATABRICKS_SCOPE = "quintoandar"
REQUEST_TIMEOUT_SECONDS = 15
# Seed for the cascade in _build_escalation_targets, used only if even the
# L0 assignee's own email can't be resolved. A level with no HR chain entry
# (or a protected executive) does NOT fall back here — it repeats the
# nearest earlier level's already-resolved target instead.
FALLBACK_OWNER_EMAIL = "gustavo.rompe@quintoandar.com.br"
# Jira Issue Property key tracking the last escalation level DMed for an
# issue. No UI representation — internal bookkeeping only, for idempotency.
ESCALATION_NOTIFIED_PROPERTY_KEY = "escalation-notified"
NOTIFICATION_HUB_WEBHOOK_BASE_KEY = "notification_hub_inmetro_webhook_base"
# Channel used only when NHI supports DM-first with space fallback on delivery
# failure. Today omitted from the webhook payload so a successful DM does not
# also post to DAG_Rotation (NHI currently posts to space whenever it is set).
GCHAT_FALLBACK_SPACE = "DAG_Rotation"


class EscalationPolicy:
    """Which escalation level is due, and how levels compare, per Criticality tier.

    LEVELS is the fixed escalation order (assignee first). DAYS_BY_CRITICALITY
    is read as a table: rows are criticality tiers, columns are levels, cells
    are "days open before this level is due" — Critical escalates in days,
    Low over weeks. Missing/unrecognized criticality uses DEFAULT_CRITICALITY.
    """

    LEVELS = ("L0", "L4", "L3", "L2")
    DEFAULT_CRITICALITY = "Medium"
    DAYS_BY_CRITICALITY = {
        #            L0  L4  L3  L2
        "Critical": (1, 2, 3, 4),
        "High": (2, 4, 6, 8),
        "Medium": (5, 8, 12, 16),
        "Low": (8, 12, 18, 24),
    }

    @classmethod
    def rank(cls, level_name: str | None) -> int:
        """Position in LEVELS, or -1 if level_name is None/unrecognized (never notified)."""
        return cls.LEVELS.index(level_name) if level_name in cls.LEVELS else -1

    @classmethod
    def target_level(cls, days_open: int | None, criticality: str | None) -> str | None:
        """Highest level whose day threshold days_open has crossed, for this criticality."""
        if days_open is None:
            return None
        days_by_level = cls.DAYS_BY_CRITICALITY.get(
            criticality, cls.DAYS_BY_CRITICALITY[cls.DEFAULT_CRITICALITY]
        )
        target = None
        for level_name, threshold_days in zip(cls.LEVELS, days_by_level):
            if days_open >= threshold_days:
                target = level_name
        return target

    @classmethod
    def is_new_level(
        cls, target_level: str | None, last_level_sent: str | None
    ) -> bool:
        """True when target_level is due and hasn't already been sent."""
        return target_level is not None and cls.rank(target_level) > cls.rank(
            last_level_sent
        )


OPEN_ISSUES_QUERY = f"""
    SELECT id_issue, assignee, assignee_account_id, ts_created, summary, criticality
    FROM datalake_jira.issues
    WHERE id_project = '{DEI_PROJECT_ID}'
      AND is_deleted = false
      AND (current_status_category IS NULL OR current_status_category != 'Done')
      AND assignee_account_id IS NOT NULL
"""

# One row per employee, with the L4/L3/L2 manager chain already walked via
# three self-joins — Trino/Spark do this join far more simply than hand-rolled
# Python dict-chasing. dim_management_hierarchy only stores a single hop
# (person_number -> person_number_manager), so unrolling 3 fixed hops is
# simplest; a recursive CTE would be overkill for a depth this shallow and
# isn't supported by Spark SQL anyway. deduped_hierarchy breaks ties on
# duplicate person_number rows deterministically (by manager identity, not
# collect() row order) so a repeat run can't silently pick a different chain.
MANAGER_CHAIN_QUERY = """
    WITH deduped_hierarchy AS (
        SELECT
            person_number,
            person_number_manager,
            email_manager,
            ROW_NUMBER() OVER (
                PARTITION BY person_number
                ORDER BY person_number_manager, email_manager
            ) AS rn
        FROM dw_people.dim_management_hierarchy
    ),
    hierarchy AS (
        SELECT person_number, person_number_manager, email_manager
        FROM deduped_hierarchy
        WHERE rn = 1
    )
    SELECT
        e.work_email AS own_email,
        e.name AS own_name,
        h1.email_manager AS l4_email,
        h2.email_manager AS l3_email,
        h3.email_manager AS l2_email
    FROM dw_people.dim_employee e
    LEFT JOIN hierarchy h1 ON h1.person_number = e.person_number
    LEFT JOIN hierarchy h2 ON h2.person_number = h1.person_number_manager
    LEFT JOIN hierarchy h3 ON h3.person_number = h2.person_number_manager
    WHERE e.work_email IS NOT NULL
"""

# dim_management_hierarchy also carries each employee's full fixed-depth
# chain to the top (email_l0..email_l9). email_l0 is the CEO for virtually
# every row (one person, company-wide) and email_l1 is that CEO's direct
# reports (the C-level/VP tier, ~10 people) — a small, data-derived set we
# never want to actually escalate an incident to, at least for now.
PROTECTED_EXECUTIVE_QUERY = """
    SELECT DISTINCT email_l0 AS email FROM dw_people.dim_management_hierarchy WHERE email_l0 <> ''
    UNION
    SELECT DISTINCT email_l1 AS email FROM dw_people.dim_management_hierarchy WHERE email_l1 <> ''
"""

logging_logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dag_name")
    parser.add_argument("schema")
    parser.add_argument("logical_ts")
    return parser.parse_args()


def _parse_logical_ts(raw: str) -> datetime:
    # No shared helper for this exists in bietlejuice-core/runtime; the same
    # few lines are already duplicated in report_open_incidents.py and
    # load_agent_alerts.py — matching that established convention rather
    # than introducing a new one-off shared util for just this job.
    text = raw.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(text)
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _days_open(ts_created: datetime | None, as_of: datetime) -> int | None:
    if ts_created is None:
        return None
    return (as_of - ts_created).days


def _build_employee_name_by_email(chain_rows: list[dict]) -> dict[str, str]:
    """Lowercased work email -> display name from MANAGER_CHAIN_QUERY."""
    lookup: dict[str, str] = {}
    for row in chain_rows:
        email = row.get("own_email")
        name = row.get("own_name")
        if not email or not name:
            continue
        lookup.setdefault(email.strip().lower(), str(name).strip())
    return lookup


def _format_assignee_display_name(
    jira_assignee_name: str | None,
    assignee_email: str | None,
    employee_names_by_email: dict[str, str],
) -> str:
    """HTML-escaped assignee label for card copy (Jira displayName, then HR name)."""
    if jira_assignee_name and str(jira_assignee_name).strip():
        return html.escape(str(jira_assignee_name).strip())
    if assignee_email:
        key = assignee_email.strip().lower()
        if key in employee_names_by_email:
            return html.escape(employee_names_by_email[key])
        local = assignee_email.split("@", 1)[0].replace(".", " ").title()
        return html.escape(local)
    return "the assignee"


def _escalation_notice(effective_level: str, assignee_display_name: str) -> str:
    """Level-specific body copy — always names the assignee and explains DEI context."""
    if effective_level == "L0":
        return (
            f"<b>{assignee_display_name}</b>, you are the assignee of this open "
            f"data incident (DEI card in Jira). It has stayed unresolved longer than "
            f"the threshold for its criticality — please review the card and move it "
            f"forward."
        )
    if effective_level == "L4":
        return (
            f"You are receiving this as the assignee's manager. "
            f"<b>{assignee_display_name}</b> on your team is responsible for an open "
            f"data incident (DEI card) that has not been resolved within the expected "
            f"timeframe. Please help unblock or reassign."
        )
    if effective_level == "L3":
        return (
            f"You are the second level in QuintoAndar's automatic escalation for open "
            f"data incidents (DEI cards). <b>{assignee_display_name}</b> on your team "
            f"is still the assignee and has not resolved this card within the expected "
            f"timeframe — your involvement is needed."
        )
    return (
        f"You are the third level in QuintoAndar's automatic escalation for open "
        f"data incidents (DEI cards). <b>{assignee_display_name}</b> on your team "
        f"is still the assignee and has not resolved this card within the expected "
        f"timeframe — please step in to unblock."
    )


def _build_manager_chain_by_email(chain_rows: list[dict]) -> dict[str, tuple]:
    """Lowercased own email -> (l4_email, l3_email, l2_email), from MANAGER_CHAIN_QUERY."""
    lookup: dict[str, tuple] = {}
    for row in sorted(
        chain_rows,
        key=lambda r: (
            r.get("own_email") or "",
            r.get("l4_email") or "",
            r.get("l3_email") or "",
            r.get("l2_email") or "",
        ),
    ):
        email = row.get("own_email")
        if not email:
            continue
        key = email.strip().lower()
        lookup.setdefault(
            key, (row.get("l4_email"), row.get("l3_email"), row.get("l2_email"))
        )
    return lookup


def _build_protected_executive_emails(rows: list[dict]) -> set[str]:
    """Lowercased emails from PROTECTED_EXECUTIVE_QUERY — never an escalation target."""
    return {row["email"].strip().lower() for row in rows if row.get("email")}


def _build_escalation_targets(
    assignee_email: str | None,
    manager_emails: tuple,
    protected_emails: set[str],
    issue_key: str,
) -> tuple:
    """For L4/L3/L2, in order: (target_email, effective_level).

    L4/L3/L2 escalate normally to the real manager chain. A level whose real
    manager is missing (no HR chain entry that far up) or a protected
    executive (CEO/VP — see PROTECTED_EXECUTIVE_QUERY) repeats the *previous*
    level's already-resolved target instead of jumping to a fixed fallback:
    escalation only ever reaches people already looped in, never a VP/CEO.
    effective_level is whose identity target_email actually represents (may
    be an earlier level than the one nominally due) — used to pick the right
    notice text on the card.
    """
    last_email = assignee_email or FALLBACK_OWNER_EMAIL
    last_level = "L0"
    targets = []
    for level_name, manager_email in zip(EscalationPolicy.LEVELS[1:], manager_emails):
        is_protected = (
            bool(manager_email) and manager_email.strip().lower() in protected_emails
        )
        if manager_email and not is_protected:
            last_email, last_level = manager_email, level_name
        else:
            reason = (
                "is a protected executive (CEO/VP)"
                if is_protected
                else "has no HR chain entry"
            )
            logging_logger.warning(
                f"m={JOB_NAME}, issue={issue_key}, msg=Escalation_{level_name} "
                f"target {reason}; repeating {last_level}'s target ({last_email}) instead"
            )
        targets.append((last_email, last_level))
    return tuple(targets)


def _target_for_level(
    level_name: str | None,
    assignee_email: str | None,
    escalation_targets: tuple,
) -> tuple[str | None, str | None]:
    """(target_email, effective_level) for level_name, or (None, None)."""
    if level_name is None:
        return None, None
    if level_name == "L0":
        return assignee_email, "L0"
    # EscalationPolicy.LEVELS is ("L0", "L4", "L3", "L2"); escalation_targets
    # is aligned to ("L4", "L3", "L2") — offset by one to skip L0.
    return escalation_targets[EscalationPolicy.LEVELS.index(level_name) - 1]


def _next_escalation_preview(
    target_level: str,
    days_open: int,
    criticality: str | None,
    assignee_email: str | None,
    escalation_targets: tuple,
) -> tuple[int, str | None] | None:
    """(days_until_next, next_target_email) for the level after target_level,
    or None when target_level is already the last one (L2). Reuses
    escalation_targets so the preview respects the same executive-protection
    cascade as the real notification — it never previews a VP/CEO either.
    """
    level_index = EscalationPolicy.LEVELS.index(target_level)
    if level_index + 1 >= len(EscalationPolicy.LEVELS):
        return None
    next_level = EscalationPolicy.LEVELS[level_index + 1]
    days_by_level = EscalationPolicy.DAYS_BY_CRITICALITY.get(
        criticality,
        EscalationPolicy.DAYS_BY_CRITICALITY[EscalationPolicy.DEFAULT_CRITICALITY],
    )
    days_until_next = days_by_level[level_index + 1] - days_open
    next_target_email, _ = _target_for_level(
        next_level, assignee_email, escalation_targets
    )
    return days_until_next, next_target_email


def _jira_auth() -> HTTPBasicAuth:
    raw_credentials = (
        BaseDBUtils()
        .get_dbutils()
        .secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.JIRA)
    )
    credentials = json.loads(raw_credentials)
    return HTTPBasicAuth(credentials["username"], credentials["token"])


def _resolve_email(account_id: str, auth: HTTPBasicAuth) -> str | None:
    try:
        response = requests.get(
            f"{JIRA_SERVER}/rest/api/3/user",
            params={"accountId": account_id},
            auth=auth,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        email = response.json().get("emailAddress")
        return email.strip().lower() if email else None
    except Exception as error:  # noqa: BLE001 — one bad lookup must not fail the whole sync
        logging_logger.warning(
            f"m={JOB_NAME}, msg=Failed to resolve email, account_id={account_id}, error={error}"
        )
        return None


def _get_escalation_notified_level(issue_key: str, auth: HTTPBasicAuth) -> str | None:
    """Last escalation level DMed for this issue, or None if never notified.

    Raises on any read failure other than a confirmed 404 (property doesn't
    exist yet). A transient error must not be mistaken for "never
    notified" -- that would resend an already-sent DM -- so callers are
    expected to catch this and skip the issue for the run instead.
    """
    response = requests.get(
        f"{JIRA_SERVER}/rest/api/3/issue/{issue_key}/properties/"
        f"{ESCALATION_NOTIFIED_PROPERTY_KEY}",
        auth=auth,
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    if response.status_code == 404:
        return None
    response.raise_for_status()
    return response.json().get("value", {}).get("last_level_sent")


def _put_escalation_notified_level(
    issue_key: str, level_name: str, as_of_date: str, auth: HTTPBasicAuth
) -> bool:
    """Write the notified-level property. Retries once (PUT is idempotent) since
    a transient failure here is exactly what causes a duplicate DM next run.
    """
    body = {"last_level_sent": level_name, "last_sent_date": as_of_date}
    for attempt in (1, 2):
        try:
            response = requests.put(
                f"{JIRA_SERVER}/rest/api/3/issue/{issue_key}/properties/"
                f"{ESCALATION_NOTIFIED_PROPERTY_KEY}",
                json=body,
                auth=auth,
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            return True
        except Exception as error:  # noqa: BLE001
            logging_logger.warning(
                f"m={JOB_NAME}, issue={issue_key}, msg=Escalation-notified property "
                f"write attempt {attempt} failed, error={error}"
            )
    return False


def _build_escalation_card(
    issue_key: str,
    summary: str | None,
    days_open: int,
    target_level: str,
    effective_level: str,
    assignee_display_name: str,
    next_preview: tuple[int, str | None] | None,
) -> dict:
    issue_url = f"{JIRA_SERVER}/browse/{issue_key}"
    lines = [
        (
            f"<b>{issue_key}</b> is an open data incident (DEI) assigned to "
            f"<b>{assignee_display_name}</b> that has been unresolved for "
            f"{days_open} day(s)."
        )
    ]
    if summary:
        # The card's other lines use literal HTML (<b>, <a href>), which Google
        # Chat renders as markup. summary is raw, reporter-controlled Jira text
        # — escape it so a crafted summary can't inject a link/tag into a DM
        # from the trusted Notification Hub bot.
        lines.append(html.escape(summary))
    lines.append(_escalation_notice(effective_level, assignee_display_name))
    if effective_level != target_level:
        lines.append(
            f"This card has escalated further up the chain, but the next contact "
            f"is company leadership, so you are being notified again as the most "
            f"recent escalation contact for <b>{assignee_display_name}</b>'s team."
        )
    if next_preview:
        days_until_next, next_email = next_preview
        if next_email:
            lines.append(
                f"Heads up: if <b>{assignee_display_name}</b>'s card is still open, "
                f"it escalates further in {days_until_next} day(s) and will notify "
                f"{html.escape(next_email)}."
            )
    lines.append(f'<a href="{issue_url}">Open in Jira</a>')
    text = "\n".join(lines)
    return {
        "cardId": f"escalation-{issue_key}-{target_level}",
        "card": {
            "header": {"title": "DEI incident escalation"},
            "sections": [{"widgets": [{"textParagraph": {"text": text}}]}],
        },
    }


def _notify_hub(webhook_base: str, email: str, card: dict) -> bool:
    # Target behaviour: DM the escalation target (assignee or manager chain via
    # ``info.email`` → ``users`` in api/configs/generic.json); if DM delivery
    # fails, fall back to ``GCHAT_FALLBACK_SPACE``. NHI does not expose delivery
    # status on the webhook response (async SQS), and setting ``space`` today
    # always posts to the channel even when DM succeeds — so we send DM-only
    # until NHI implements conditional fallback (+ plain-text @mention in DM).
    payload = {
        "cardsV2": [card],
        "info": {"email": [email], "mention": True},
    }
    try:
        response = requests.post(
            webhook_base, json=payload, timeout=REQUEST_TIMEOUT_SECONDS
        )
        response.raise_for_status()
        return True
    except Exception as error:  # noqa: BLE001 — one failed notify must not fail the whole sync
        logging_logger.warning(
            f"m={JOB_NAME}, msg=Failed to notify via Notification Hub, error={error}"
        )
        return False


def _load_environment_config(dag_name: str, environment: str) -> dict:
    conf_file = f"{environment}_conf.yml"
    try:
        raw = DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            dag_name, conf_file
        )
    except FileNotFoundError:
        logging_logger.warning(
            f"m={JOB_NAME}, dag_name={dag_name}, conf_file={conf_file}, "
            "msg=Spark jobs env conf not found"
        )
        return {}
    return yaml.safe_load(raw) or {}


def _notification_hub_webhook_base(config: dict) -> str | None:
    value = config.get(NOTIFICATION_HUB_WEBHOOK_BASE_KEY)
    return str(value).strip() if value else None


def _maybe_notify_escalation(
    issue_key: str,
    days_open: int | None,
    criticality: str | None,
    assignee_email: str | None,
    assignee_display_name: str,
    escalation_targets: tuple,
    webhook_base: str | None,
    summary: str | None,
    logical_ts: datetime,
    auth: HTTPBasicAuth,
) -> tuple[str, str | None, str] | None:
    """Attempt to DM the newly-reached escalation level, if any.

    Returns (level_due, target_email, status) when a level was newly due this
    run — status is "sent", "sent_property_write_failed", "failed", or
    "skipped_no_email" — or None when nothing was due (no threshold crossed
    yet, already sent previously, or the notified-level read failed this run).
    """
    target_level = EscalationPolicy.target_level(days_open, criticality)
    if not target_level or not webhook_base:
        return None

    try:
        last_level_sent = _get_escalation_notified_level(issue_key, auth)
    except Exception as error:  # noqa: BLE001 — skip, don't risk a duplicate DM
        logging_logger.warning(
            f"m={JOB_NAME}, issue={issue_key}, msg=Failed to read escalation-notified "
            f"property; skipping this run to avoid resending an already-sent level, "
            f"error={error}"
        )
        return None
    if not EscalationPolicy.is_new_level(target_level, last_level_sent):
        return None

    target_email, effective_level = _target_for_level(
        target_level, assignee_email, escalation_targets
    )
    if not target_email:
        logging_logger.warning(
            f"m={JOB_NAME}, issue={issue_key}, msg=No email to notify "
            f"Escalation_{target_level}; skipping"
        )
        return target_level, None, "skipped_no_email"

    next_preview = _next_escalation_preview(
        target_level, days_open, criticality, assignee_email, escalation_targets
    )
    card = _build_escalation_card(
        issue_key,
        summary,
        days_open,
        target_level,
        effective_level,
        assignee_display_name,
        next_preview,
    )
    if not _notify_hub(webhook_base, target_email, card):
        return target_level, target_email, "failed"

    if not _put_escalation_notified_level(
        issue_key, target_level, logical_ts.date().isoformat(), auth
    ):
        logging_logger.error(
            f"m={JOB_NAME}, issue={issue_key}, msg=DM sent for {target_level} but "
            f"the escalation-notified property write failed; the next run may "
            f"resend this level"
        )
        return target_level, target_email, "sent_property_write_failed"
    return target_level, target_email, "sent"


def main() -> None:
    args = parse_arguments()
    logical_ts = _parse_logical_ts(args.logical_ts)

    spark_client = SparkClient(app_name=JOB_NAME)
    spark = spark_client.conn

    open_issues = [row.asDict() for row in spark.sql(OPEN_ISSUES_QUERY).collect()]
    chain_rows = [row.asDict() for row in spark.sql(MANAGER_CHAIN_QUERY).collect()]
    manager_chain_by_email = _build_manager_chain_by_email(chain_rows)
    employee_names_by_email = _build_employee_name_by_email(chain_rows)
    protected_rows = [
        row.asDict() for row in spark.sql(PROTECTED_EXECUTIVE_QUERY).collect()
    ]
    protected_emails = _build_protected_executive_emails(protected_rows)
    logging_logger.info(
        f"m={JOB_NAME}, open_issues={len(open_issues)}, chain_rows={len(chain_rows)}, "
        f"protected_executives={len(protected_emails)}"
    )

    config = _load_environment_config(args.dag_name, args.environment)
    webhook_base = _notification_hub_webhook_base(config)
    if not webhook_base:
        logging_logger.warning(
            f"m={JOB_NAME}, msg=Notification Hub webhook base not configured; "
            "skipping escalation DMs"
        )
    auth = _jira_auth()

    # Memoized per account_id for this run — the same assignee recurs across
    # many issues, and each lookup is a network call.
    @cache
    def resolve_email(account_id: str) -> str | None:
        return _resolve_email(account_id, auth)

    notification_counts: dict[str, int] = {}

    for issue in open_issues:
        issue_key = issue["id_issue"]
        assignee_account_id = issue["assignee_account_id"]
        assignee_email = resolve_email(assignee_account_id)
        assignee_display_name = _format_assignee_display_name(
            issue.get("assignee"),
            assignee_email,
            employee_names_by_email,
        )
        summary = issue.get("summary")
        criticality = issue.get("criticality")
        days_open = _days_open(issue.get("ts_created"), logical_ts)

        manager_emails = manager_chain_by_email.get(
            (assignee_email or "").strip().lower(), (None, None, None)
        )
        escalation_targets = _build_escalation_targets(
            assignee_email, manager_emails, protected_emails, issue_key
        )

        result = _maybe_notify_escalation(
            issue_key,
            days_open,
            criticality,
            assignee_email,
            assignee_display_name,
            escalation_targets,
            webhook_base,
            summary,
            logical_ts,
            auth,
        )
        if result is None:
            continue
        _level_due, _notified_email, notification_status = result
        notification_counts[notification_status] = (
            notification_counts.get(notification_status, 0) + 1
        )

    logging_logger.info(
        f"m={JOB_NAME}, open_issues={len(open_issues)}, "
        f"notification_counts={notification_counts}"
    )


if __name__ == "__main__":
    main()
