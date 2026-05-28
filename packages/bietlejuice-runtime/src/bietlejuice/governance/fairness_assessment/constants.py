"""All module-level constants for the fairness_assessment package (job, TDQ, tiering, DataHub GraphQL)."""

from __future__ import annotations

import re
from typing import Final, FrozenSet

# ---------------------------------------------------------------------------
# Spark job: lake table FQNs (driver)
# ---------------------------------------------------------------------------

JOB_NAME = "load_fairness_assessment"

TABLES_DOC = "datalake_documentation_metrics_clean.tables_documentation"
COLUMNS_DOC = "datalake_documentation_metrics_clean.columns_documentation"
COLUMNS_METASTORE = ("datalake_documentation_metrics_clean", "columns_metastore")
ORG_CHART = "datalake_people_public.org_chart"

DAG_INVENTORY = "datalake_dag_inventory_clean.table"
DAG_INVENTORY_DAG_PREFIX = "bietlejuice"
DAG_INVENTORY_PRODUCTIVE_LAYERS: FrozenSet[str] = frozenset(
    {"raw", "clean", "enrich", "dw", "core", "metric"}
)

# F1-03 / I1-01 — snapshot-based catalog signals (see adapters.columns_metastore).
# Reason *values* kept for dashboards / SQL reports that key off these strings.
FQN_NOT_IN_COLUMNS_METASTORE_REASON = "fqn_not_in_columns_metastore_snapshot"
COLUMNS_METASTORE_SNAPSHOT_UNAVAILABLE_REASON = "columns_metastore_snapshot_unavailable"
SCHEMA_NOT_IN_COLUMNS_METASTORE_REASON = (
    "spark_schema_not_in_columns_metastore_snapshot"
)
DOCUMENTED_NOT_IN_PHYSICAL_REASON = "documented_not_in_physical"

# ---------------------------------------------------------------------------
# Metadata YAML: ``domain`` (CI Yamale + F2-01)
# ---------------------------------------------------------------------------
# Must stay identical to the alternation inside ``domain: regex('...')`` in
# ``packages/bietlejuice-compiler/scripts/services/metadata_file_schemas/*_schema.yml``.
# Includes ``Data Platform`` (core-layer metadata) in addition to the governance allowlist.
# F2-01 uses :func:`re.fullmatch` on the trimmed value; empty domain skips regex (``domain_missing`` only).

METADATA_DOMAIN_CI_ALLOWLIST_PATTERN: Final[str] = (
    "Agents|Cross|Data Ops & Governance|Data Life Cycle|Fintech|For Rent|For Sale|"
    "Growth|International|MLOps|People|QCX|Rede|Support and Services|Tech Platform|Data Platform|"
    "Conversational XP|DS Pricing|Atlas DB|Broker XP"
)
METADATA_DOMAIN_CI_ALLOWLIST_RE = re.compile(METADATA_DOMAIN_CI_ALLOWLIST_PATTERN)

# ---------------------------------------------------------------------------
# Table / column description quality (TDQ) heuristics
# ---------------------------------------------------------------------------
# Calibrate against production sample before tightening tier gates.

TDQ_MIN_SUBSTANTIVE_EXTRA_WORDS = 2
TDQ_MIN_DESC_CHARS = 24
TDQ_MAX_NAME_OVERLAP_RATIO = 0.82

TDQ_WORD_RE = re.compile(r"\w+", re.UNICODE)

TDQ_STOPWORDS: FrozenSet[str] = frozenset(
    {
        "a",
        "o",
        "os",
        "as",
        "um",
        "uma",
        "de",
        "da",
        "do",
        "das",
        "dos",
        "em",
        "no",
        "na",
        "nos",
        "nas",
        "para",
        "por",
        "com",
        "sem",
        "sobre",
        "este",
        "esta",
        "estes",
        "estas",
        "esse",
        "essa",
        "the",
        "an",
        "of",
        "in",
        "on",
        "for",
        "to",
        "and",
        "or",
        "at",
        "by",
        "from",
        "with",
        "that",
        "this",
        "these",
        "those",
        "there",
        "their",
        "its",
        "it",
        "is",
        "are",
        "was",
        "were",
        "be",
        "been",
        "being",
        "have",
        "has",
        "had",
        "does",
        "did",
        "doing",
        "will",
        "would",
        "could",
        "should",
        "may",
        "might",
        "must",
        "can",
        "not",
        "nor",
        "only",
        "also",
        "just",
        "than",
        "too",
        "very",
        "each",
        "every",
        "all",
        "any",
        "both",
        "few",
        "more",
        "most",
        "some",
        "such",
        "other",
        "into",
        "through",
        "during",
        "before",
        "after",
        "above",
        "below",
        "between",
        "under",
        "again",
        "here",
        "where",
        "when",
        "what",
        "which",
        "who",
        "how",
        "why",
        "about",
        "against",
    }
)

TDQ_BOILERPLATE_TOKENS: FrozenSet[str] = frozenset(
    {
        "tabela",
        "table",
        "dataset",
        "datasets",
        "dados",
        "data",
        "informacoes",
        "informações",
        "information",
        "lista",
        "list",
        "contem",
        "contém",
        "contains",
        "registros",
        "records",
        "rows",
        "linhas",
        "base",
        "camada",
        "layer",
        "schema",
        "hive",
        "delta",
        "database",
        "databases",
        "warehouse",
        "datalake",
        "lakehouse",
        "field",
        "fields",
        "column",
        "columns",
        "entry",
        "entries",
        "source",
        "sources",
        "staging",
        "partition",
        "partitions",
        "mart",
        "marts",
        "bronze",
        "silver",
        "gold",
        "curated",
        "pipeline",
        "pipelines",
    }
)

TDQ_BOILERPLATE_PHRASES: tuple[str, ...] = (
    "table containing information about",
    "table with information about",
    "table with data about",
    "tabela com informações de",
    "tabela com informacoes de",
    "tabela com dados de",
    "contains information about",
    "contain information about",
    "contém informações",
    "contem informacoes",
    "contains information",
    "information about",
    "information on",
    "tabela de dados",
    "dataset com",
    "dataset with",
    "datasets com",
    "datasets with",
    "dados de",
    "data from",
    "data about",
    "informações de",
    "informacoes de",
    "lista de",
    "list of",
)

# ---------------------------------------------------------------------------
# Tiering (MVP and full) — also used by I1-01 for partition column names
# ---------------------------------------------------------------------------

# Tier 1 — Findable and Accessible (explicit list from spike §3.1)
TIER_1_IDS: FrozenSet[str] = frozenset(
    {
        "F1-01",
        "F1-02",
        "F1-03",
        "F2-01",
        "F4-01",
        "A1-03",
        "A1.2-03",
        "I1-02",
        "R1.3-01",
        "R1.3-02",
    }
)

TIER_2_EXTRA: FrozenSet[str] = frozenset(
    {"F2-02", "A1.2-02", "I1-01", "I2-01", "I3-01", "I3-02"}
)
TIER_3_EXTRA: FrozenSet[str] = frozenset(
    {"R1-01", "R1-02", "R1-04", "R1-05", "R1.1-01", "R1.2-01"}
)
TIER_4_EXTRA: FrozenSet[str] = frozenset(
    {"F3-01", "I2-02", "R1-03", "R1-06", "R1.1-02"}
)

# Active Tier-1 slice for this rollout: A1-03 still deferred; A1.2-03 scored via interim contract proxy
# (see check_a1_2_03_interim_access_policy_via_contract); R1.3-* out of scope (naming / CI-CD).
TIER1_ACTIVE_REQUIREMENT_IDS: FrozenSet[str] = frozenset(
    {
        "F1-01",
        "F1-02",
        "F1-03",
        "F2-01",
        "F4-01",
        "A1.2-03",
        "I1-02",
    }
)

# Tier-1 slice + Tier-2 (program) column-doc richness + lake ↔ Spark name coverage
MVP_TIER2_SCOPED_REQUIREMENT_IDS: FrozenSet[str] = TIER1_ACTIVE_REQUIREMENT_IDS | {
    "F2-02",
    "I1-01",
}

MVP_IMPLEMENTED_REQUIREMENT_IDS: FrozenSet[str] = frozenset(
    MVP_TIER2_SCOPED_REQUIREMENT_IDS
)

# F2-02: partition column names excluded from substantive description checks (lowercase)
PARTITION_COLUMN_NAMES_LOWERCASE: FrozenSet[str] = frozenset({"year", "month", "day"})

# Bump when FAIR tiering requirement ID sets from governance change
TIERING_RULES_VERSION = "fairness-tiering-spike-2026-04-v12"

# ---------------------------------------------------------------------------
# DataHub GraphQL: default endpoints by environment
# ---------------------------------------------------------------------------
# Same URLs as ``datahub_graphql_url`` in ``forno_conf.yml`` / ``prod_conf.yml``; keep in sync if infra
# changes. Fairness Spark job may default to these when ``DATAHUB_GRAPHQL_URL`` is unset.

DATAHUB_GRAPHQL_URL_FORNO = "https://datahub-gms.apps.data-frn.habitat.zone/api/graphql"
DATAHUB_GRAPHQL_URL_PROD = "https://datahub-gms.apps.data-prd.habitat.zone/api/graphql"


def graphql_url_for_environment(environment: str) -> str:
    """Default DataHub GraphQL base URL for the Spark ``environment`` argument.

    Airflow passes ``environment`` as ``forno`` or ``prod`` (first job argument). Override with
    ``DATAHUB_GRAPHQL_URL`` when needed (see DAG ``README.md``).
    """

    if (environment or "").strip().lower() == "forno":
        return DATAHUB_GRAPHQL_URL_FORNO
    return DATAHUB_GRAPHQL_URL_PROD


# ---------------------------------------------------------------------------
# DataHub GraphQL: HTTP/response tokens, F4, contract marker, query text
# ---------------------------------------------------------------------------
# String *values* are stable (checks_result_json / URN diags); Python names use DATAHUB_ prefix.

DATAHUB_HTTP_ERROR = "HTTP_ERROR"
DATAHUB_FETCH_ERROR = "FETCH_ERROR"
DATAHUB_ENTITY_NOT_FOUND = "ENTITY_NOT_FOUND"
DATAHUB_CHECK_FAILED = "DATAHUB_CHECK_FAILED"

# Downstream override token: when DataHub is unreachable for an FQN (HTTP/FETCH error on F4-01),
# I1-02 / I3-01 / I3-02 / A1.2-03 expose this single reason instead of their content-based defaults
# (e.g. ``no_assigned_data_contract_urn_in_databricks_entity``) which would mislead consumers into
# treating an infra outage as missing metadata.
DATAHUB_UNREACHABLE_REASON = "datahub_unreachable"

DATAHUB_F4_REASON_HOST_UNCONFIGURED = "datahub_host_unconfigured"
DATAHUB_F4_REASON_NO_CANDIDATE_URNS = "datahub_no_candidate_platform_urns"

# Per-URN: fetch resolved with non-empty aspects (driver-only; not a consumer-facing failure code).
DATAHUB_URN_DIAG_OK = "OK"

DATAHUB_DATA_CONTRACT_URN_MARKER = "urn:prod:datacontract:"

# GraphQL batching defaults: 25 URNs per POST × 4 driver workers = 100 URNs in flight.
# Both knobs accept env overrides (``DATAHUB_GRAPHQL_BATCH_SIZE`` / ``DATAHUB_GRAPHQL_BATCH_WORKERS``)
# resolved in ``compute_fqn_datahub_signals.resolve_datahub_urn_flags`` at call time, mirroring the
# ``DATAHUB_GRAPHQL_URL`` env-first pattern so forno operators can tune without redeploying.
DATAHUB_GRAPHQL_BATCH_SIZE = 25
DATAHUB_GRAPHQL_BATCH_WORKERS = 4
DATAHUB_GRAPHQL_BATCH_TIMEOUT_SEC = 60.0

DATAHUB_DATASET_FAIR_SIGNALS_QUERY = """
query DatasetFairSignals($urn: String!) {
  dataset(urn: $urn) {
    exists
    ownership {
      owners {
        owner {
          ... on CorpUser { urn }
          ... on CorpGroup { urn }
        }
      }
    }
    upstream: lineage(input: { direction: UPSTREAM, start: 0, count: 0 }) {
      total
    }
    downstream: lineage(input: { direction: DOWNSTREAM, start: 0, count: 0 }) {
      total
    }
    institutionalMemory {
      elements {
        label
        url
      }
    }
  }
}
"""
