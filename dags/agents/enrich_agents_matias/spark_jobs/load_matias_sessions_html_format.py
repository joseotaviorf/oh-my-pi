# load_matias_sessions_html_format — writes
# datalake_agents_matias.matias_sessions_html_format
# (merge id_session; partitions year/month/day).
#
# One HTML transcript row per Matias (ian) session, derived from
# datalake_agents_matias.eval_session_bundle. Walks the nested conversation
# in Python (no explode of the bundle) so product/QA can inspect turns,
# tool/agent path, knowledge-base hits and automatic eval cards.
#
# Source
# ------
# - datalake_agents_matias.eval_session_bundle
# - datalake_knowledge_base_clean.bot_content  (article titles; LEFT lookup)

from __future__ import annotations

import json
import re
from argparse import ArgumentParser, Namespace
from datetime import date, datetime, timedelta, timezone
from html import escape
from typing import Any, Iterable, Mapping, Optional, Sequence
from zoneinfo import ZoneInfo

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.functions import col, lit
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_matias_sessions_html_format"
SOURCE_TABLE_NAME = "eval_session_bundle"
KB_TABLE_NAME = "datalake_knowledge_base_clean.bot_content"
logger = QuintoAndarLogger(JOB_NAME)

BRT = ZoneInfo("America/Sao_Paulo")
_AGENT_SKIP_RE = re.compile(r"(?i)input|reactplanner|^clear_")
_KB_TOOL_RE = re.compile(r"^search_broker_documents_v\d+$")
_CONTENT_ID_RE = r'"content_id"\s*:\s*"?([^"}\],\s]+)'
_MONTHS_PT = (
    "janeiro",
    "fevereiro",
    "março",
    "abril",
    "maio",
    "junho",
    "julho",
    "agosto",
    "setembro",
    "outubro",
    "novembro",
    "dezembro",
)
_NATURALNESS_LABEL = {
    2: "Natural",
    1: "Somewhat Robotic",
    0: "Robotic",
}
_TOOL_ARG_KEYS = (
    "instructions",
    "query",
    "answer_to_supervisor",
    "message_to_user",
)
HTML_STRUCT = StructType(
    [
        StructField("conversation_html", StringType()),
        StructField("conversation_with_traces_html", StringType()),
        StructField("evals", StringType()),
    ]
)
ARG_SPEC = [
    ("env", str, "forno", "Environment: forno/prod"),
    ("datalake_bucket", str, "5a-datalake-prod", "Datalake bucket"),
    ("database_base_name", str, "agents_matias", "Base name for database (schema)"),
    ("dag_name", str, "enrich_agents_matias", "DAG name (for alignment with Airflow)"),
    ("table_name", str, "matias_sessions_html_format", "Target enrich table name"),
    (
        "load_start_date",
        str,
        lambda: (date.today() - timedelta(days=90)).isoformat(),
        "Inclusive session_date window start, format %Y-%m-%d",
    ),
    (
        "load_end_date",
        str,
        lambda: date.today().isoformat(),
        "Inclusive session_date window end, format %Y-%m-%d",
    ),
    ("run_mode", str, "dev", "Run mode: prod/dev"),
]


def parse_args() -> Namespace:
    """Parse CLI args. Uses parse_known_args() so Databricks kernel flags are ignored."""
    parser = ArgumentParser(description=JOB_NAME)
    default_values = [d() if callable(d) else d for _, _, d, _ in ARG_SPEC]
    for (name, type_, _default, help_text), default_val in zip(
        ARG_SPEC, default_values
    ):
        parser.add_argument(
            name, nargs="?", type=type_, default=default_val, help=help_text
        )
    add_validation_target_args(parser)
    namespace, _ = parser.parse_known_args()
    return namespace


# Plain-Python helpers (no Spark). Unit-tested without a session.


def escape_text(value: Any) -> str:
    """HTML-escape untrusted session text so transcripts cannot store XSS."""
    if value is None:
        return ""
    return escape(str(value), quote=True)


def _as_plain(value: Any) -> Any:
    if value is None:
        return None
    as_dict = getattr(value, "asDict", None)
    if callable(as_dict):
        return {key: _as_plain(val) for key, val in as_dict().items()}
    if isinstance(value, Mapping):
        return {key: _as_plain(val) for key, val in value.items()}
    if isinstance(value, (list, tuple)):
        return [_as_plain(item) for item in value]
    return value


def _parse_json(raw: Any) -> Any:
    if raw is None or raw == "":
        return None
    if isinstance(raw, (dict, list)):
        return raw
    try:
        return json.loads(raw)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None


def _as_brt(ts: Any) -> Optional[datetime]:
    if ts is None:
        return None
    parsed = ts
    if isinstance(ts, str):
        try:
            parsed = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            return None
    if not isinstance(parsed, datetime):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(BRT)


def _fmt_hm(ts: Any) -> str:
    converted = _as_brt(ts)
    if converted is None:
        return ""
    return converted.strftime("%H:%M")


def _fmt_full(ts: Any) -> str:
    converted = _as_brt(ts)
    if converted is None:
        return ""
    return converted.strftime("%Y-%m-%d %H:%M:%S")


def format_date_pt(ts: Any) -> str:
    converted = _as_brt(ts)
    if converted is None:
        return ""
    return f"{converted.day} de {_MONTHS_PT[converted.month - 1]} de {converted.year}"


def _first(*values: Any) -> Any:
    for value in values:
        if value is not None and value != "":
            return value
    return None


def _join_texts(values: Iterable[Any], sep: str = "\n") -> str:
    parts = [
        str(item).strip() for item in values if item is not None and str(item).strip()
    ]
    return sep.join(parts)


def parse_trace_input_text(trace_input: Any) -> str:
    payload = _parse_json(trace_input) or {}
    messages = payload.get("messages") if isinstance(payload, dict) else None
    if not isinstance(messages, list):
        return ""
    return _join_texts(item.get("text") for item in messages if isinstance(item, dict))


def parse_trace_output_text(trace_output: Any) -> str:
    payload = _parse_json(trace_output) or {}
    responses = payload.get("responses") if isinstance(payload, dict) else None
    if not isinstance(responses, list):
        return ""
    parts = []
    for item in responses:
        if not isinstance(item, dict):
            continue
        content = item.get("content") if isinstance(item.get("content"), dict) else {}
        parts.append(_first(content.get("full_text"), item.get("response_type")))
    return _join_texts(parts)


def parse_notifications(trace_input: Any) -> list[dict]:
    payload = _parse_json(trace_input) or {}
    if not isinstance(payload, dict):
        return []
    user_context = payload.get("user_context") or {}
    if not isinstance(user_context, dict):
        return []
    raw = user_context.get("user_last_notifications") or []
    if isinstance(raw, str):
        raw = _parse_json(raw) or []
    if not isinstance(raw, list):
        return []
    notifications = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        notifications.append(
            {
                "template": item.get("template"),
                "text": item.get("text"),
                "sent_at": item.get("sent_at"),
            }
        )
    return notifications


def _tool_calls(output_json: Any) -> list[dict]:
    if not isinstance(output_json, dict):
        return []
    calls = output_json.get("tool_calls") or []
    return [call for call in calls if isinstance(call, dict)]


def _is_kb_search_tool(name: Any) -> bool:
    return bool(_KB_TOOL_RE.match(str(name or "")))


def _normalize_kb_titles(kb_titles: Optional[Mapping[Any, Any]]) -> dict[str, str]:
    """Spark collect() keeps native types; lookups always use str(content_id)."""
    if not kb_titles:
        return {}
    return {
        str(key): str(title)
        for key, title in kb_titles.items()
        if key is not None and title not in (None, "")
    }


def _iter_json_payloads(raw: Any) -> list[Any]:
    """Unwrap MCP / Langfuse wrappers around the tool JSON."""
    parsed = raw if isinstance(raw, (dict, list)) else _parse_json(raw)
    if parsed is None:
        return []
    payloads: list[Any] = [parsed]
    if not isinstance(parsed, dict):
        return payloads
    for key in ("content", "result", "output", "data"):
        inner = parsed.get(key)
        if isinstance(inner, str):
            nested = _parse_json(inner)
            if nested is not None:
                payloads.append(nested)
        elif isinstance(inner, dict):
            payloads.append(inner)
        elif isinstance(inner, list):
            payloads.append(inner)
            for item in inner:
                if not isinstance(item, dict):
                    continue
                text = item.get("text")
                if isinstance(text, str):
                    nested = _parse_json(text)
                    if nested is not None:
                        payloads.append(nested)
    return payloads


def extract_articles(output_json: Any) -> list[dict]:
    articles: list[dict] = []
    seen: set[str] = set()
    for payload in _iter_json_payloads(output_json):
        candidates: list[Any] = []
        if isinstance(payload, dict) and isinstance(payload.get("articles"), list):
            candidates = payload["articles"]
        elif isinstance(payload, list):
            candidates = payload
        for article in candidates:
            if not isinstance(article, dict):
                continue
            content_id = _article_content_id(article)
            key = content_id or str(id(article))
            if key in seen:
                continue
            seen.add(key)
            articles.append(article)
    return articles


def _article_content_id(article: Mapping[str, Any]) -> Optional[str]:
    raw = article.get("content_id")
    if raw is None:
        raw = article.get("id_content")
    if raw is None or raw == "":
        return None
    return str(raw)


def _article_title(article: Mapping[str, Any], kb_titles: Mapping[str, str]) -> str:
    embedded = article.get("title") or article.get("name")
    if embedded:
        return str(embedded)
    content_id = _article_content_id(article)
    if content_id:
        looked_up = kb_titles.get(content_id)
        if looked_up:
            return looked_up
    return ""


def parse_observation(
    observation: Mapping[str, Any], kb_titles: Mapping[str, str]
) -> list[dict]:
    """Turn one Langfuse observation into one or more HTML observation cards."""
    titles = _normalize_kb_titles(kb_titles)
    output_json = _parse_json(observation.get("output"))
    calls = _tool_calls(output_json)
    name = _join_texts(call.get("name") for call in calls)
    if not name and isinstance(output_json, dict):
        content = (
            output_json.get("content")
            if isinstance(output_json.get("content"), dict)
            else {}
        )
        if content.get("moderated") is not None:
            name = "moderated"
        elif content.get("complete_answer") is not None:
            name = "complete_answer"

    arguments = _join_texts(_tool_call_argument_html(call) for call in calls)
    if not arguments and isinstance(output_json, dict):
        content = (
            output_json.get("content")
            if isinstance(output_json.get("content"), dict)
            else {}
        )
        arguments = (
            _first(content.get("moderated"), content.get("complete_answer")) or ""
        )

    cards = []
    if name or arguments:
        cards.append(
            {
                "ts_started": observation.get("started_at")
                or observation.get("ts_started"),
                "name": name or observation.get("name") or "",
                "arguments": arguments,
            }
        )

    if observation.get("type") == "TOOL" and _is_kb_search_tool(
        observation.get("name")
    ):
        kb_args = _kb_arguments(output_json, titles)
        if kb_args:
            cards.append(
                {
                    "ts_started": observation.get("started_at")
                    or observation.get("ts_started"),
                    "name": "📚 knowledge_base_content_used",
                    "arguments": kb_args,
                }
            )
    return cards


def _tool_call_argument_html(call: Mapping[str, Any]) -> str:
    args = call.get("args") if isinstance(call.get("args"), dict) else {}
    for key in _TOOL_ARG_KEYS:
        value = args.get(key)
        if value:
            label = escape_text(f"{key}: ")
            return (
                f'<span style="color:#8b93a1;font-size:11px;font-weight:600">'
                f"{label}</span><br>{escape_text(value)}"
            )
    return ""


def _kb_arguments(output_json: Any, kb_titles: Mapping[str, str]) -> str:
    titles = _normalize_kb_titles(kb_titles)
    lines = []
    for article in extract_articles(output_json):
        content_id = _article_content_id(article)
        if not content_id:
            continue
        title = _article_title(article, titles)
        label = f"{content_id} - {title}" if title else content_id
        lines.append(f"{escape_text(label)}<br>")
    return "\n".join(lines)


def agents_and_tools(observations: Sequence[Mapping[str, Any]]) -> tuple[str, str]:
    agents = []
    tools = []
    for observation in observations:
        name = observation.get("name") or ""
        obs_type = observation.get("type")
        if obs_type == "AGENT" and name and not _AGENT_SKIP_RE.search(name):
            if name not in agents:
                agents.append(name)
        elif obs_type == "TOOL" and name and name not in tools:
            tools.append(name)
    return ", ".join(agents), ", ".join(tools)


def turn_latency_sec(observations: Sequence[Mapping[str, Any]]) -> Optional[int]:
    starts = [
        _as_brt(obs.get("started_at") or obs.get("ts_started")) for obs in observations
    ]
    ends = [_as_brt(obs.get("ended_at") or obs.get("ts_ended")) for obs in observations]
    starts = [ts for ts in starts if ts is not None]
    ends = [ts for ts in ends if ts is not None]
    if not starts or not ends:
        return None
    return int((max(ends) - min(starts)).total_seconds())


def turn_output_ended_at(
    item: Mapping[str, Any], observations: Sequence[Mapping[str, Any]]
) -> Any:
    ends = [obs.get("ended_at") or obs.get("ts_ended") for obs in observations]
    ends = [ts for ts in ends if ts is not None]
    if ends:
        return max(
            ends,
            key=lambda ts: _as_brt(ts) or datetime.min.replace(tzinfo=timezone.utc),
        )
    return item.get("message_ts")


def parse_trace_turn_text(
    item: Mapping[str, Any], trace: Mapping[str, Any]
) -> tuple[str, str]:
    """User/bot bubble text for one Langfuse trace (user-turn anchor in the bundle)."""
    sender = (item.get("message_sender") or "").lower()
    message = (item.get("message") or "").strip()
    input_text = parse_trace_input_text(trace.get("input"))
    output_text = parse_trace_output_text(trace.get("output"))
    if sender == "user":
        input_text = input_text or message
    elif sender == "bot":
        output_text = output_text or message
    return input_text, output_text


def clean_eval_name(name: str) -> str:
    lowered = (name or "").lower()
    if "frustration" in lowered:
        return "Frustration"
    if "naturalness" in lowered:
        return "Naturalness"
    if "friction" in lowered:
        return "Friction"
    if "resolution" in lowered:
        return "Resolution"
    if "laborlitigationrisk" in lowered or (
        "labor" in lowered and "litigation" in lowered
    ):
        return "Labor Litigation Risk"
    if "airesistance" in lowered or "resistance" in lowered:
        return "AI Resistance"
    cleaned = re.sub(r"evaluator", "", lowered)
    cleaned = re.sub(r"eval", "", cleaned)
    cleaned = re.sub(r"matias", "", cleaned)
    cleaned = re.sub(r"^ian", "", cleaned)
    return cleaned.strip(" _-").replace("_", " ").title()


def display_eval_value(name: str, value: Any, string_value: Any) -> str:
    if "naturalness" in (name or "").lower():
        try:
            return _NATURALNESS_LABEL[int(value)]
        except (TypeError, ValueError, KeyError):
            pass
    if string_value not in (None, ""):
        return str(string_value)
    if value is None:
        return ""
    try:
        return str(round(float(value), 2)).rstrip("0").rstrip(".")
    except (TypeError, ValueError):
        return str(value)


def render_eval_cards(evals: Any) -> str:
    cards = []
    for name, value, string_value in _eval_entries(evals):
        cards.append(
            '<div style="background:#1c2028;border:1px solid #2a2f3a;border-radius:10px;'
            'padding:14px 16px;min-width:150px;flex:1 1 45%">'
            '<div style="color:#8b93a1;font-size:12px;font-weight:600;margin-bottom:6px">'
            f"📊 {escape_text(clean_eval_name(name))}</div>"
            '<div style="color:#e8a33d;font-size:12px;font-weight:700">'
            f"{escape_text(display_eval_value(name, value, string_value))}</div></div>"
        )
    if not cards:
        return ""
    return (
        '<div style="color:#8b93a1;font-size:12px;font-weight:700;letter-spacing:0.08em;'
        'margin:0 0 12px 4px">📊 AVALIAÇÕES AUTOMÁTICAS</div>'
        '<div style="display:flex;flex-wrap:wrap;gap:10px;margin-bottom:16px">'
        f"{''.join(cards)}</div>"
    )


def _eval_entries(evals: Any) -> list[tuple[str, Any, Any]]:
    plain = _as_plain(evals)
    if not plain:
        return []
    if isinstance(plain, Mapping):
        items = list(plain.items())
    elif isinstance(plain, list):
        items = []
        for entry in plain:
            if isinstance(entry, Mapping) and entry.get("name"):
                items.append((entry["name"], entry))
    else:
        return []
    rows = []
    for name, payload in items:
        if isinstance(payload, Mapping):
            rows.append((str(name), payload.get("value"), payload.get("string_value")))
        else:
            rows.append((str(name), payload, None))
    return rows


def render_summary(
    session_date: Any,
    message_count: int,
    avg_latency: Optional[float],
    max_latency: Optional[float],
    trace_count: int,
    id_session: str,
) -> str:
    date_label = format_date_pt(session_date)
    avg_label = "" if avg_latency is None else str(avg_latency)
    max_label = "" if max_latency is None else str(max_latency)
    return (
        '<div style="display:flex;flex-wrap:wrap;gap:16px;align-items:center;color:#8b93a1;'
        "font-size:13px;padding:10px 0;border-top:1px solid #2a2f3a;"
        'border-bottom:1px solid #2a2f3a;margin-bottom:16px">'
        f"<span>🗓 {escape_text(date_label)}</span>"
        f"<span>💬 {message_count} mensagens</span>"
        f"<span>⏱ latência média {escape_text(avg_label)}s  máxima {escape_text(max_label)}s</span>"
        f"<span>🔎 {trace_count} traces</span>"
        f'<span style="color:#5b6270">ID: {escape_text(id_session)}</span></div>'
    )


def render_date_pill(session_date: Any) -> str:
    date_label = format_date_pt(session_date)
    if not date_label:
        return ""
    return (
        '<div style="text-align:center;margin:16px 0">'
        '<span style="background:#232830;color:#8b93a1;font-size:12px;padding:4px 14px;'
        f'border-radius:14px">{escape_text(date_label)}</span></div>'
    )


def render_notifications(notifications: Sequence[Mapping[str, Any]]) -> str:
    if not notifications:
        return ""
    cards = []
    ordered = sorted(notifications, key=lambda item: str(item.get("sent_at") or ""))
    for item in ordered:
        template = item.get("template") or "Notificação"
        cards.append(
            '<div style="background:#1c2028;border:1px solid #d9822b;border-radius:8px;'
            'padding:10px 14px;margin:0 0 8px 0">'
            '<div style="color:#d9822b;font-weight:700;font-size:12px;margin-bottom:2px">'
            f"Template: {escape_text(template)}</div>"
            '<div style="color:#5b6270;font-size:10px;margin-bottom:6px">'
            f"{escape_text(_fmt_full(item.get('sent_at')))}</div>"
            f'<div style="color:#c7cbd1;font-size:13px">{escape_text(item.get("text"))}</div>'
            "</div>"
        )
    return (
        '<div style="color:#8b93a1;font-size:12px;font-weight:700;letter-spacing:0.08em;'
        'margin:0 0 12px 4px">🔔 NOTIFICAÇÕES RECEBIDAS</div>'
        f"{''.join(cards)}"
    )


def render_observation_card(name: str, arguments: str) -> str:
    return (
        '<div style="background:#181b21;border:1px solid #262b34;border-radius:8px;'
        'padding:8px 10px;margin:4px 0">'
        f'<span style="color:#e8a33d;font-size:11px;font-weight:600">{escape_text(name)}</span>'
        f'<div style="color:#c7cbd1;font-size:12px;margin-top:6px">{arguments}</div></div>'
    )


def _user_bubble(text: str, ts: Any) -> str:
    if not text:
        return ""
    return (
        '<div style="display:flex;justify-content:flex-end;margin-bottom:8px">'
        '<div style="background:#2f7a57;color:#fff;border-radius:12px 12px 2px 12px;'
        'padding:10px 14px;max-width:70%;font-size:14px">'
        f"{escape_text(text)}"
        '<div style="text-align:right;color:rgba(255,255,255,0.7);font-size:10px;margin-top:4px">'
        f"{escape_text(_fmt_hm(ts))}</div></div></div>"
    )


def _bot_bubble(
    text: str, ts: Any, latency: Optional[int], label: str = "Matias"
) -> str:
    latency_label = "" if latency is None else f"{latency}s · "
    return (
        '<div style="display:flex;justify-content:flex-start">'
        '<div style="background:#1c2028;border:1px solid #2a2f3a;color:#e6e8eb;'
        'border-radius:12px 12px 12px 2px;padding:10px 14px;max-width:75%;font-size:14px">'
        f'<div style="color:#3ecf8e;font-weight:700;font-size:12px;margin-bottom:4px">{label}</div>'
        f"{escape_text(text)}"
        '<div style="text-align:right;color:#5b6270;font-size:10px;margin-top:6px">'
        f"{escape_text(_fmt_hm(ts))} · {escape_text(latency_label)}"
        "</div></div></div>"
    )


def _agents_tools_line(agents: str, tools: str) -> str:
    if not agents and not tools:
        return ""
    return (
        '<div style="color:#5b6270;font-size:11px;margin:6px 0 0 4px">'
        f"🤖 {escape_text(agents)}&nbsp;&nbsp;🔧 {escape_text(tools)}&nbsp;&nbsp;</div>"
    )


def _observations_block(
    observations: Sequence[Mapping[str, Any]], kb_titles: Mapping[str, str]
) -> str:
    cards = []
    for observation in observations:
        cards.extend(parse_observation(observation, kb_titles))
    cards.sort(key=lambda card: str(card.get("ts_started") or ""))
    if not cards:
        return ""
    body = "\n".join(
        render_observation_card(card["name"], card["arguments"]) for card in cards
    )
    return (
        '<div style="margin:8px 0 0 4px">'
        '<div style="color:#8b93a1;font-size:11px;font-weight:600;margin-bottom:4px">'
        f"Observations</div>{body}</div>"
    )


def render_turn(
    user_text: str,
    bot_text: str,
    user_ts: Any,
    bot_ts: Any,
    latency: Optional[int],
    agents: str,
    tools: str,
    observations: Sequence[Mapping[str, Any]],
    kb_titles: Mapping[str, str],
    include_observations: bool,
    bot_label: str = "Matias",
) -> str:
    """One visual turn: optional user bubble + optional Matias/analyst bubble."""
    parts = [
        '<div style="margin-bottom:20px">',
        _user_bubble(user_text, user_ts),
        _bot_bubble(bot_text, bot_ts, latency, bot_label) if bot_text else "",
        _agents_tools_line(agents, tools),
    ]
    if include_observations:
        parts.append(_observations_block(observations, kb_titles))
    parts.append("</div>")
    return "".join(parts)


def render_trace_turn(
    item: Mapping[str, Any],
    trace: Mapping[str, Any],
    kb_titles: Mapping[str, str],
    include_observations: bool,
) -> str:
    observations = [
        obs for obs in (trace.get("observations") or []) if isinstance(obs, Mapping)
    ]
    input_text, output_text = parse_trace_turn_text(item, trace)
    agents, tools = agents_and_tools(observations)
    latency = turn_latency_sec(observations)
    return render_turn(
        user_text=input_text,
        bot_text=output_text,
        user_ts=trace.get("started_at") or item.get("message_ts"),
        bot_ts=turn_output_ended_at(item, observations),
        latency=latency,
        agents=agents,
        tools=tools,
        observations=observations,
        kb_titles=kb_titles,
        include_observations=include_observations,
    )


def render_message_turn(
    item: Mapping[str, Any],
    kb_titles: Mapping[str, str],
    include_observations: bool,
) -> str:
    sender = (item.get("message_sender") or "").lower()
    text = (item.get("message") or "").strip()
    if sender == "system" or not text:
        return ""
    label = "Analista" if sender == "analyst" else "Matias"
    if sender == "user":
        return render_turn(
            user_text=text,
            bot_text="",
            user_ts=item.get("message_ts"),
            bot_ts=None,
            latency=None,
            agents="",
            tools="",
            observations=[],
            kb_titles=kb_titles,
            include_observations=include_observations,
        )
    return render_turn(
        user_text="",
        bot_text=text,
        user_ts=None,
        bot_ts=item.get("message_ts"),
        latency=None,
        agents="",
        tools="",
        observations=[],
        kb_titles=kb_titles,
        include_observations=include_observations,
        bot_label=label,
    )


def _wrap(body: str) -> str:
    return (
        '<div style="background:#12151a;border-radius:14px;padding:20px;'
        f'font-family:sans-serif">{body}</div>'
    )


def render_session(
    id_session: str,
    conversation: Sequence[Any],
    evals: Any,
    session_started_at: Any,
    kb_titles: Optional[Mapping[str, str]] = None,
) -> dict:
    titles = _normalize_kb_titles(kb_titles)
    items = [
        item for item in (_as_plain(conversation) or []) if isinstance(item, Mapping)
    ]
    notifications = []
    latencies = []
    trace_count = 0
    message_count = 0
    simple_turns = []
    full_turns = []
    for item in items:
        traces = [
            trace for trace in (item.get("traces") or []) if isinstance(trace, Mapping)
        ]
        sender = (item.get("message_sender") or "").lower()
        if traces:
            trace_count += len(traces)
            notifications.extend(parse_notifications(traces[0].get("input")))
            for trace in traces:
                observations = [
                    obs
                    for obs in (trace.get("observations") or [])
                    if isinstance(obs, Mapping)
                ]
                latency = turn_latency_sec(observations)
                if latency is not None:
                    latencies.append(latency)
                message_count += 2
                simple_turns.append(render_trace_turn(item, trace, titles, False))
                full_turns.append(render_trace_turn(item, trace, titles, True))
            continue
        # Bot text already lives in the previous user-turn traces (anchor logic).
        if sender in ("system", "bot"):
            continue
        if sender == "user":
            message_count += 1
        simple_turns.append(render_message_turn(item, titles, False))
        full_turns.append(render_message_turn(item, titles, True))

    avg_latency = round(sum(latencies) / len(latencies), 1) if latencies else None
    max_latency = round(max(latencies), 1) if latencies else None
    session_date = session_started_at or (items[0].get("message_ts") if items else None)
    evals_html = render_eval_cards(evals)
    header = (
        render_summary(
            session_date,
            message_count,
            avg_latency,
            max_latency,
            trace_count,
            id_session or "",
        )
        + render_date_pill(session_date)
        + render_notifications(notifications)
    )
    return {
        "conversation_html": _wrap(header + "".join(simple_turns)),
        "conversation_with_traces_html": _wrap(
            evals_html + header + "".join(full_turns)
        ),
        "evals": evals_html,
    }


# Spark I/O — one read of the bundle, then a per-session Python render.


def _kb_title_map(spark: SparkSession, bundle_df: DataFrame, kb_table: str) -> dict:
    """id_content/id (string) → title, for KB tool hits in this window."""
    observations = bundle_df.select(
        F.explode_outer(
            F.expr(
                "flatten(transform(coalesce(conversation, array()), m -> "
                "flatten(transform(coalesce(m.traces, array()), t -> "
                "coalesce(t.observations, array())))))"
            )
        ).alias("obs")
    ).filter(F.col("obs.name").rlike(r"^search_broker_documents_v\d+$"))
    ids = (
        observations.select(
            F.explode_outer(
                F.regexp_extract_all(
                    F.col("obs.output").cast("string"),
                    F.lit(_CONTENT_ID_RE),
                    F.lit(1),
                )
            ).alias("content_id")
        )
        .select(F.col("content_id").cast("string").alias("content_id"))
        .filter(F.col("content_id").isNotNull() & (F.col("content_id") != ""))
        .distinct()
        .alias("ids")
    )
    kb = (
        spark.table(kb_table)
        .select(
            F.col("id").cast("string").alias("id"),
            F.col("id_content").cast("string").alias("id_content"),
            F.col("title"),
        )
        .filter(F.col("title").isNotNull())
        .alias("kb")
    )
    matched = (
        kb.join(ids, F.col("kb.id_content") == F.col("ids.content_id"), "inner")
        .select(F.col("ids.content_id"), F.col("kb.title"))
        .union(
            kb.join(ids, F.col("kb.id") == F.col("ids.content_id"), "inner").select(
                F.col("ids.content_id"), F.col("kb.title")
            )
        )
        .dropDuplicates(["content_id"])
    )
    return _normalize_kb_titles(
        {row.content_id: row.title for row in matched.collect()}
    )


def _render_column(kb_titles: Mapping[str, str]):
    titles = _normalize_kb_titles(kb_titles)

    def _render(id_session, conversation, evals, session_started_at):
        rendered = render_session(
            id_session=id_session,
            conversation=conversation,
            evals=evals,
            session_started_at=session_started_at,
            kb_titles=titles,
        )
        return (
            rendered["conversation_html"],
            rendered["conversation_with_traces_html"],
            rendered["evals"],
        )

    return F.udf(_render, HTML_STRUCT)


def build_matias_sessions_html_format(
    spark: SparkSession,
    source_table: str,
    load_start_date: str,
    load_end_date: str,
    kb_titles: Optional[Mapping[str, str]] = None,
    kb_table: str = KB_TABLE_NAME,
) -> DataFrame:
    """One HTML row per session in [load_start_date, load_end_date] (inclusive)."""
    start = date.fromisoformat(load_start_date)
    end = date.fromisoformat(load_end_date)
    windowed = spark.table(source_table).filter(
        (col("session_date") >= lit(start)) & (col("session_date") <= lit(end))
    )
    titles = (
        kb_titles if kb_titles is not None else _kb_title_map(spark, windowed, kb_table)
    )
    with_local_ts = windowed.withColumn(
        "session_started_at",
        F.from_utc_timestamp(col("session_start_ts"), "America/Sao_Paulo"),
    )
    rendered = with_local_ts.withColumn(
        "html",
        _render_column(titles)(
            col("id_langfuse_session"),
            col("conversation"),
            col("evals"),
            col("session_started_at"),
        ),
    )
    return rendered.select(
        col("id_langfuse_session").alias("id_session"),
        col("session_started_at"),
        col("bot").alias("host_name"),
        col("is_escalated"),
        col("channel"),
        col("active_feature_flags"),
        col("html.conversation_with_traces_html").alias(
            "conversation_with_traces_html"
        ),
        col("html.conversation_html").alias("conversation_html"),
        col("html.evals").alias("evals"),
        F.year("session_started_at").alias("year"),
        F.month("session_started_at").alias("month"),
        F.dayofmonth("session_started_at").alias("day"),
    )


def _save_to_enrich(
    spark_client: SparkClient, result_df: DataFrame, args: Namespace, row_count: int
) -> None:
    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=args.table_name,
            prod_location=database_location,
            bucket=args.datalake_bucket,
            target_database=getattr(args, "target_database_name", None),
            target_table=getattr(args, "target_table_name", None),
        )
    )
    full_table_name = f"{write_database_name}.{write_table_name}"
    s3_path = f"{write_location}{write_table_name}"

    MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    ).create_database(write_database_name)
    DeltaLoader(spark_client.conn).load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=["year", "month", "day"],
        merge_schema=True,
        merge_on=["id_session"],
    )
    MetastoreServiceFactory.create_loader_metastore_service(spark_client).refresh_table(
        write_database_name, write_table_name
    )
    priv = TablePrivileges.from_environment_default(full_table_name)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()
    logger.info(f"m=save_df, table={full_table_name}, rows={row_count:,}")


def save_df(spark_client: SparkClient, result_df: DataFrame, args: Namespace) -> None:
    run_mode = args.run_mode
    if run_mode == "dev":
        view_name = f"dev_{args.table_name}"
        result_df.cache()
        dev_row_count = result_df.count()
        result_df.createOrReplaceTempView(view_name)
        logger.info(
            f"Dev mode: registered temp view '{view_name}' ({dev_row_count:,} rows). "
            f"Query with: SELECT * FROM {view_name}"
        )
        return
    if run_mode == "prod":
        row_count = result_df.count()
        if row_count == 0:
            logger.warning("m=save_df, msg=no rows in window; skip Delta write")
            return
        _save_to_enrich(spark_client, result_df, args, row_count)
        return
    raise ValueError(f"Invalid run mode: {run_mode}")


def main(args: Optional[Namespace] = None) -> None:
    """Orchestrate ETL: read bundle → render HTML → write enrich table."""
    if args is None:
        args = parse_args()
    logger.info(
        f"m=main, run_mode={args.run_mode}, env={args.env}, "
        f"database_base_name={args.database_base_name}, table_name={args.table_name}, "
        f"data_interval=[{args.load_start_date}, {args.load_end_date}], "
        f"msg=Starting Spark job"
    )

    spark_client = SparkClient(app_name=JOB_NAME)
    source_db = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )["db_enrich_databricks"]
    source_table = f"{source_db}.{SOURCE_TABLE_NAME}"
    logger.info(f"m=main, source_table={source_table}")

    output_df = build_matias_sessions_html_format(
        spark_client.conn, source_table, args.load_start_date, args.load_end_date
    )
    save_df(spark_client, output_df, args)
    logger.info("m=main, msg=Job finished successfully")


if __name__ == "__main__":
    main()
