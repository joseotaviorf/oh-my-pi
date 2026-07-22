"""Cluster resolution for Databricks and EMR validation runs."""

from __future__ import annotations

import json
import logging
import re
import subprocess
import time
from datetime import date
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import yaml

from emr_runner import (
    describe_cluster_json,
    ensure_aws_credentials,
    list_clusters_json,
    run_emr_cli,
)

logger = logging.getLogger(__name__)

SKILL_DIR = Path(__file__).resolve().parent
SESSION_FILE = SKILL_DIR / ".session.yml"

REUSABLE_EMR_STATES = {"WAITING", "RUNNING"}
DEAD_EMR_STATES = {"TERMINATED", "TERMINATING"}

# EC2 instance profile (JobFlowRole) overrides for domain-scoped buckets/secrets.
# DAGs under dags/people require emr-people-prod (not the default emr-prod).
DEFAULT_JOB_FLOW_ROLE = "emr-prod"
DOMAIN_JOB_FLOW_ROLES = {
    "people": "emr-people-prod",
}
DEFAULT_DOMAIN_TAG = "default"

CLUSTER_GONE_ERROR_MARKERS = (
    "terminat",
    "not in a valid state",
    "cluster not found",
    "invalid cluster",
    "cannot add steps",
)


def job_flow_role_for_domain(domain: Optional[str]) -> str:
    """Return the EMR JobFlowRole (instance profile) for a DAG domain folder."""
    if not domain:
        return DEFAULT_JOB_FLOW_ROLE
    return DOMAIN_JOB_FLOW_ROLES.get(str(domain).strip().lower(), DEFAULT_JOB_FLOW_ROLE)


def domain_tag_for_domain(domain: Optional[str]) -> str:
    """Return the Domain EMR tag value used to reuse validation clusters safely."""
    if not domain:
        return DEFAULT_DOMAIN_TAG
    normalized = str(domain).strip().lower()
    if normalized in DOMAIN_JOB_FLOW_ROLES:
        return normalized
    return DEFAULT_DOMAIN_TAG


def cluster_domain_tag(cluster_id: str, region: str = "us-east-1") -> Optional[str]:
    """Read Domain tag from an EMR cluster.

    Missing ``Domain`` tag means the default profile. Describe failures return
    ``None`` so callers treat the cluster as unknown (never invent a match).
    """
    del region
    try:
        tags = describe_cluster_json(cluster_id).get("tags") or {}
    except RuntimeError as exc:
        logger.warning("Could not describe EMR cluster %s for Domain tag: %s", cluster_id, exc)
        return None
    return str(tags.get("Domain") or DEFAULT_DOMAIN_TAG)


def cluster_matches_domain(cluster_id: str, domain: Optional[str], region: str = "us-east-1") -> bool:
    """True when the cluster Domain tag matches the profile required by ``domain``."""
    actual = cluster_domain_tag(cluster_id, region=region)
    if actual is None:
        return False
    return actual == domain_tag_for_domain(domain)


def load_session() -> Dict[str, Any]:
    if not SESSION_FILE.exists():
        return {}
    with SESSION_FILE.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def save_session(data: Dict[str, Any]) -> None:
    SESSION_FILE.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def clear_session_emr_cluster(cluster_id: str) -> None:
    session = load_session()
    if session.get("emr_cluster_id") == cluster_id:
        session.pop("emr_cluster_id", None)
        save_session(session)
        logger.warning("Cleared stale emr_cluster_id from session: %s", cluster_id)


def _databricks_env(profile: str) -> Dict[str, str]:
    import os

    env = os.environ.copy()
    env.pop("DATABRICKS_USERNAME", None)
    env["DATABRICKS_CONFIG_PROFILE"] = profile
    return env


def validate_databricks_cluster(cluster_id: str, profile: str) -> str:
    result = subprocess.run(
        ["databricks", "clusters", "get", cluster_id, "--profile", profile, "--output", "json"],
        capture_output=True,
        text=True,
        env=_databricks_env(profile),
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Failed to get cluster details")

    cluster = json.loads(result.stdout)
    state = cluster.get("state")
    if state != "RUNNING":
        raise RuntimeError(f"Cluster {cluster_id} is not RUNNING (state: {state})")

    name = cluster.get("cluster_name", "")
    if name.lower().startswith("job-"):
        raise RuntimeError(
            f"Cluster {cluster_id} looks like a job cluster ({name}). "
            "Provide a running all-purpose cluster id."
        )
    return cluster_id


def resolve_databricks_cluster(cluster_id: Optional[str], profile: str) -> str:
    """Validate an explicit Databricks all-purpose cluster id (no auto-discovery)."""
    if not cluster_id or not str(cluster_id).strip():
        raise RuntimeError(
            "Databricks cluster id is required. Pass --cluster with a running "
            "all-purpose cluster id (job-* clusters are rejected)."
        )
    validated = validate_databricks_cluster(str(cluster_id).strip(), profile)
    session = load_session()
    session["databricks_cluster_id"] = validated
    session["databricks_profile"] = profile
    save_session(session)
    return validated


def update_session_after_compare(
    *,
    domain: str,
    dag_name: str,
    report_path: Path,
    results: List[Any],
    load_start_date: str,
    load_end_date: str,
    databricks_cluster_id: str,
    emr_cluster_id: str,
) -> None:
    from report import aggregate_dag_status

    session = load_session()
    session["databricks_cluster_id"] = databricks_cluster_id
    session["emr_cluster_id"] = emr_cluster_id
    session["load_start_date"] = load_start_date
    session["load_end_date"] = load_end_date
    session["baseline_dir"] = str(SKILL_DIR / "baseline")
    session["last_validation_date"] = str(date.today())
    session["last_report_path"] = str(report_path)

    dag_key = f"{domain}/{dag_name}"
    passed_dags = list(session.get("passed_dags") or [])
    failed_dags = list(session.get("failed_dags") or [])
    _, _, failed, _manual, pr_allowed = aggregate_dag_status(results)

    if dag_key in passed_dags:
        passed_dags.remove(dag_key)
    if dag_key in failed_dags:
        failed_dags.remove(dag_key)

    if pr_allowed:
        passed_dags.append(dag_key)
    else:
        failed_dags.append(dag_key)

    session["passed_dags"] = passed_dags
    session["failed_dags"] = failed_dags
    save_session(session)


def describe_emr_cluster(cluster_id: str, region: str = "us-east-1") -> str:
    del region
    return str(describe_cluster_json(cluster_id).get("state", ""))


def is_emr_cluster_reusable(cluster_id: str, region: str = "us-east-1") -> Tuple[bool, str]:
    del region
    try:
        state = describe_emr_cluster(cluster_id)
    except RuntimeError as exc:
        logger.warning("Could not describe EMR cluster %s: %s", cluster_id, exc)
        return False, "UNAVAILABLE"
    if state in REUSABLE_EMR_STATES:
        return True, state
    if state in DEAD_EMR_STATES:
        logger.warning("EMR cluster %s is %s — skipping", cluster_id, state)
        clear_session_emr_cluster(cluster_id)
    return False, state


def is_cluster_gone_error(message: str) -> bool:
    lower = message.lower()
    return any(marker in lower for marker in CLUSTER_GONE_ERROR_MARKERS)


def list_active_emr_clusters(region: str = "us-east-1") -> list[dict]:
    """Return EMR clusters currently in WAITING or RUNNING state."""
    del region
    return [
        {
            "id": cluster.get("id"),
            "name": cluster.get("name", ""),
            "state": cluster.get("state"),
        }
        for cluster in list_clusters_json()
        if cluster.get("state") in REUSABLE_EMR_STATES
    ]


def list_reusable_emr_cluster_ids(region: str = "us-east-1") -> List[str]:
    """All reusable cluster ids — WAITING first, then RUNNING."""
    active = list_active_emr_clusters(region)
    if active:
        logger.info("Active reusable EMR clusters:")
        for cluster in active:
            logger.info("  %s  %s  %s", cluster["id"], cluster["state"], cluster["name"])

    ordered: List[str] = []
    for preferred_state in ("WAITING", "RUNNING"):
        for cluster in active:
            if cluster["state"] == preferred_state:
                ordered.append(cluster["id"])
    return ordered


def is_migration_validation_cluster(cluster_id: str, region: str = "us-east-1") -> bool:
    """True when cluster was created by emr-cli for migration (Purpose=migration-validation)."""
    del region
    try:
        tags = describe_cluster_json(cluster_id).get("tags") or {}
    except RuntimeError as exc:
        logger.warning("Could not describe EMR cluster %s for tag check: %s", cluster_id, exc)
        return False
    return tags.get("Purpose") == "migration-validation"


def find_emr_clusters_by_tag(
    tag_value: str = "migration-validation",
    region: str = "us-east-1",
) -> List[str]:
    """Return all active cluster ids tagged ``Purpose=<tag_value>``."""
    del region
    clusters = list_clusters_json(tag_key="Purpose", tag_value=tag_value)
    return [str(cluster["id"]) for cluster in clusters if cluster.get("id")]


def find_emr_cluster_by_tag(
    tag_value: str = "migration-validation",
    region: str = "us-east-1",
) -> Optional[str]:
    """Return the first active cluster id tagged ``Purpose=<tag_value>`` (legacy)."""
    ids = find_emr_clusters_by_tag(tag_value=tag_value, region=region)
    return ids[0] if ids else None


def create_emr_cluster(emr_env: str = "prod", *, domain: Optional[str] = None) -> str:
    role = job_flow_role_for_domain(domain)
    domain_tag = domain_tag_for_domain(domain)
    logger.info(
        "Creating migration-validation EMR cluster (Domain=%s, JobFlowRole=%s)",
        domain_tag,
        role,
    )
    returncode, output = run_emr_cli(
        [
            "create-cluster",
            "--name",
            f"migration-validation-{domain_tag}-{int(time.time())}",
            "--job-flow-role",
            role,
            "--tag",
            "Purpose=migration-validation",
            "--tag",
            "Owner=emr-migration-validate",
            "--tag",
            f"Domain={domain_tag}",
            "--tag",
            f"JobFlowRole={role}",
        ],
        emr_env=emr_env,
    )
    if returncode != 0:
        raise RuntimeError(output.strip() or "migration-emr-cli create-cluster failed")

    match = re.search(r"j-[A-Z0-9]+", output)
    if not match:
        raise RuntimeError("Could not parse EMR cluster id from migration-emr-cli output")
    cluster_id = match.group(0)
    _wait_for_emr_cluster(cluster_id, emr_env=emr_env)
    return cluster_id


def _wait_for_emr_cluster(
    cluster_id: str,
    region: str = "us-east-1",
    timeout_sec: int = 900,
    *,
    emr_env: str = "prod",
) -> None:
    del region
    start = time.time()
    while time.time() - start < timeout_sec:
        try:
            state = describe_cluster_json(cluster_id, emr_env=emr_env).get("state", "")
        except RuntimeError as exc:
            logger.warning(
                "Could not describe EMR cluster %s while waiting (will retry): %s",
                cluster_id,
                exc,
            )
            time.sleep(15)
            continue
        logger.info("EMR cluster %s state: %s", cluster_id, state)
        if state == "WAITING":
            return
        if state in DEAD_EMR_STATES:
            raise RuntimeError(f"EMR cluster {cluster_id} failed to start ({state})")
        time.sleep(15)
    raise TimeoutError(f"Timed out waiting for EMR cluster {cluster_id}")


def _save_validation_session(
    cluster_id: str,
    emr_env: str,
    *,
    domain: Optional[str] = None,
) -> None:
    session = load_session()
    session["emr_cluster_id"] = cluster_id
    session["emr_env"] = emr_env
    session["emr_domain"] = domain_tag_for_domain(domain)
    session["emr_job_flow_role"] = job_flow_role_for_domain(domain)
    save_session(session)


def resolve_validation_emr_cluster(
    emr_cluster_id: Optional[str],
    emr_env: str = "prod",
    *,
    new_session: bool = False,
    allow_create: bool = True,
    region: str = "us-east-1",
    domain: Optional[str] = None,
) -> str:
    """Dedicated emr-cli cluster for Phase 4 (LogUri under ``cli/`` — never fleet DAG clusters).

    Resolution order:
    1. ``--new-emr-session`` → always create a new migration-validation cluster
    2. Explicit ``--emr-cluster`` if still WAITING/RUNNING and Domain tag matches
       (Domain mismatch fails hard — never silently discard an explicit override)
    3. ``.session.yml`` ``emr_cluster_id`` if tagged ``migration-validation``, Domain matches, reusable
    4. All tagged ``Purpose=migration-validation`` clusters (Domain match)
    5. Create new cluster via ``emr-cli create-cluster`` with domain JobFlowRole

    For ``dags/people``, JobFlowRole is ``emr-people-prod``; otherwise ``emr-prod``.
    """
    ensure_aws_credentials(emr_env, region=region)
    expected_domain = domain_tag_for_domain(domain)
    expected_role = job_flow_role_for_domain(domain)

    if new_session:
        session = load_session()
        old_id = session.get("emr_cluster_id")
        if old_id:
            logger.info("Starting new validation session — dropping session cluster %s", old_id)
            session.pop("emr_cluster_id", None)
            save_session(session)

    if not new_session:
        candidates: List[str] = []
        if emr_cluster_id:
            candidates.append(emr_cluster_id)
        session = load_session()
        if session.get("emr_cluster_id"):
            candidates.append(str(session["emr_cluster_id"]))
        candidates.extend(find_emr_clusters_by_tag(region=region))

        seen: Set[str] = set()
        for cluster_id in candidates:
            if not cluster_id or cluster_id in seen:
                continue
            seen.add(cluster_id)
            is_explicit = bool(emr_cluster_id and cluster_id == emr_cluster_id)
            if is_explicit:
                pass  # allow without Purpose tag check; Domain still enforced below
            elif not is_migration_validation_cluster(cluster_id, region):
                logger.info(
                    "Skipped %s — not a migration-validation emr-cli cluster",
                    cluster_id,
                )
                continue
            if not cluster_matches_domain(cluster_id, domain, region):
                actual_domain = cluster_domain_tag(cluster_id, region)
                actual_label = (
                    actual_domain if actual_domain is not None else "unknown"
                )
                if is_explicit:
                    raise RuntimeError(
                        f"Explicit --emr-cluster {cluster_id} has Domain={actual_label} "
                        f"but this run requires Domain={expected_domain} "
                        f"(JobFlowRole={expected_role}). Pass a matching cluster, "
                        "omit --emr-cluster to auto-resolve, or use --new-emr-session."
                    )
                logger.info(
                    "Skipped %s — Domain tag %s != expected %s (JobFlowRole %s)",
                    cluster_id,
                    actual_label,
                    expected_domain,
                    expected_role,
                )
                continue
            reusable, state = is_emr_cluster_reusable(cluster_id, region)
            if reusable:
                _save_validation_session(cluster_id, emr_env, domain=domain)
                logger.info(
                    "Using validation EMR cluster %s (%s, Domain=%s, JobFlowRole=%s)",
                    cluster_id,
                    state,
                    expected_domain,
                    expected_role,
                )
                return cluster_id
            if is_explicit:
                logger.warning(
                    "Explicit --emr-cluster %s is not reusable (%s) — continuing resolution",
                    cluster_id,
                    state,
                )
            else:
                logger.info("Skipped validation EMR cluster %s (%s)", cluster_id, state)

    if not allow_create:
        raise RuntimeError(
            "No reusable migration-validation EMR cluster and --no-create-emr was set. "
            "Run without --no-create-emr or pass --new-emr-session."
        )

    logger.info(
        "Creating dedicated emr-cli validation cluster "
        "(Domain=%s, JobFlowRole=%s, step logs under emr/logs/cli/)",
        expected_domain,
        expected_role,
    )
    cluster_id = create_emr_cluster(emr_env, domain=domain)
    _save_validation_session(cluster_id, emr_env, domain=domain)
    return cluster_id


def resolve_emr_cluster(
    emr_cluster_id: Optional[str],
    emr_env: str = "prod",
    allow_create: bool = True,
    region: str = "us-east-1",
    exclude: Optional[Set[str]] = None,
    domain: Optional[str] = None,
) -> str:
    """Backward-compatible alias — always uses dedicated validation cluster resolution."""
    del exclude  # fleet failover removed; only dedicated clusters
    return resolve_validation_emr_cluster(
        emr_cluster_id,
        emr_env,
        allow_create=allow_create,
        region=region,
        domain=domain,
    )


def failover_emr_cluster(
    dead_cluster_id: str,
    emr_env: str = "prod",
    allow_create: bool = True,
    region: str = "us-east-1",
    domain: Optional[str] = None,
) -> str:
    """Replace a dead validation cluster with a new emr-cli cluster (never fleet)."""
    logger.warning("Failover: validation cluster %s is gone or terminating", dead_cluster_id)
    clear_session_emr_cluster(dead_cluster_id)
    return resolve_validation_emr_cluster(
        emr_cluster_id=None,
        emr_env=emr_env,
        new_session=True,
        allow_create=allow_create,
        region=region,
        domain=domain,
    )
