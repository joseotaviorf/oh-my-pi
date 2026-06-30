# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "apache-airflow==2.11.0",
#     "bietlejuice-core",
#     "bietlejuice-airflow",
# ]
# ///
"""
EMR terminate-emr-cluster wiring smoke: build minimal DAG graphs per touched workflow
type and print evidence that every cluster work task is a direct upstream of terminate.

Run:
  uv run --project packages/bietlejuice-airflow python test/unit/base/airflow/emr_terminate_workflow_smoke.py
"""

from __future__ import annotations

import json
import os
import sys
from contextlib import ExitStack
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import List, Optional
from unittest.mock import MagicMock, patch

# Stub private runtime packages (same as test/unit/conftest.py).
for _private_pkg in (
    "databricks_plugin",
    "databricks_plugin.hooks",
    "databricks_plugin.hooks.databricks_hook",
    "extra_link_plugin",
    "quintoandar_logger",
):
    sys.modules.setdefault(_private_pkg, MagicMock())

# ruff: noqa: E402 — imports follow databricks_plugin stubs (see test/unit/conftest.py).
from datetime import datetime

from airflow.models import DAG
from airflow.operators.empty import EmptyOperator

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.dw_query_delta_workflow import (
    DwQueryDeltaWorkflow,
)

# Repo packages on PYTHONPATH when run via uv --project bietlejuice-airflow
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.enrich_query_delta_workflow import (
    EnrichQueryDeltaWorkflow,
)
from bietlejuice.base.airflow.job_cluster_engine import collect_emr_cluster_work_tasks
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.environment_enum import EnvironmentEnum
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService

REPO_ROOT = Path(__file__).resolve().parents[6]


def _slug(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in name)


DAG_ARGS = {"name": "emr_terminate_smoke", "owner": "Data Engineering"}
EMR_CLUSTER = {"type": "emr_7_12_med_general_cluster"}


@dataclass
class SmokeResult:
    workflow: str
    status: str  # PASS | FAIL | SKIP
    terminate_task_id: Optional[str] = None
    execute_task_id: Optional[str] = None
    collected_work_tasks: List[str] = field(default_factory=list)
    terminate_upstreams: List[str] = field(default_factory=list)
    missing_from_terminate: List[str] = field(default_factory=list)
    accessory_upstreams: List[str] = field(default_factory=list)
    error: Optional[str] = None


def _install_emr_plugin():
    fake = MagicMock()
    fake.QuintoAndarEmrCreateClusterOperator = MagicMock(side_effect=_emr_op)
    fake.QuintoAndarEmrSubmitStepsOperator = MagicMock(side_effect=_emr_op)
    fake.QuintoAndarEmrTerminateClusterOperator = MagicMock(side_effect=_emr_op)
    fake.QuintoAndarEmrSubmitStepsOperator.build_spark_submit_step = MagicMock(
        return_value={
            "Name": "step",
            "ActionOnFailure": "CONTINUE",
            "HadoopJarStep": {},
        }
    )
    return patch.dict(sys.modules, {"emr_plugin": fake})


def _emr_op(*args, **kwargs):
    task_id = kwargs.get("task_id", "emr-task")
    dag = kwargs.get("dag")
    trigger_rule = kwargs.get("trigger_rule", "all_success")
    op = EmptyOperator(task_id=task_id, dag=dag, trigger_rule=trigger_rule)
    return op


def _dag_patches():
    return (
        patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.JiraOpsCallback"
        ),
        patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.DatabricksIncidentContextEnricher"
        ),
        patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.BaseDAG.get_default_trigger_form_params",
            return_value={},
        ),
    )


def _config_service_mock():
    svc = MagicMock()
    svc._deep_update = lambda a, b: {**a, **(b or {})}
    svc.get_config.side_effect = lambda key: {
        "emr_7_12_med_general_cluster": {"spark_version": "emr-7-12"},
        "emr_7_12_consolidation_xs_memory_cluster": {"spark_version": "emr-7-12"},
        "consolidation_m_general_cluster": {"spark_version": "16.4.x-scala2.12"},
        "datalake_bucket": "datalake-bucket",
        "dw_bucket": "dw-bucket",
        "incoming_bucket": "incoming-bucket",
        "metrics_bucket": "metrics-bucket",
        "databricks_bietlejuice_repo_path": "s3://repo",
        "wonka_cluster": {"spark_version": "emr-7-12"},
        "default_access_control_list": [
            {"group_name": "g", "permission_level": "CAN_MANAGE"}
        ],
        "default_libraries": [],
        "artifacts_bucket": "art",
    }.get(key, {"spark_version": "emr-7-12"})
    return svc


def _table(
    name: str = "smoke_table", layer: LayerEnum = LayerEnum.ENRICH
) -> TableAttributes:
    return TableAttributes(
        DAG_ARGS,
        {
            "type": "query_delta",
            "layer": layer.value,
            "custom_schema": "smoke",
            "has_hive_sync": True,
        },
        layer,
        name,
    )


def _verify_dag(dag: DAG, workflow_name: str) -> SmokeResult:
    execute = None
    terminate = None
    for task in dag.tasks:
        if task.task_id == "execute-job-cluster" or task.task_id.startswith(
            "execute-job-cluster-"
        ):
            execute = task
        if task.task_id == "terminate-emr-cluster" or task.task_id.startswith(
            "terminate-emr-cluster-"
        ):
            terminate = task

    if execute is None or terminate is None:
        return SmokeResult(
            workflow=workflow_name,
            status="SKIP",
            error="no execute-job-cluster or terminate-emr-cluster in DAG",
        )

    collected = collect_emr_cluster_work_tasks(execute, terminate)
    collected_ids = sorted({t.task_id for t in collected})
    upstream_ids = set(terminate.upstream_task_ids)
    missing = sorted(set(collected_ids) - upstream_ids)
    if not collected_ids:
        return SmokeResult(
            workflow=workflow_name,
            status="FAIL",
            execute_task_id=execute.task_id,
            terminate_task_id=terminate.task_id,
            terminate_upstreams=sorted(upstream_ids),
            error="collector found no work tasks between execute and terminate",
        )
    accessories = sorted(
        tid
        for tid in upstream_ids
        if any(
            token in tid
            for token in ("register", "sync", "data-quality", "data_quality")
        )
    )

    return SmokeResult(
        workflow=workflow_name,
        status="PASS" if not missing else "FAIL",
        execute_task_id=execute.task_id,
        terminate_task_id=terminate.task_id,
        collected_work_tasks=collected_ids,
        terminate_upstreams=sorted(upstream_ids),
        missing_from_terminate=missing,
        accessory_upstreams=accessories,
    )


def _new_dag(name: str) -> DAG:
    return DAG(
        dag_id=f"smoke_{_slug(name)}",
        schedule=None,
        start_date=datetime(2026, 1, 1),
    )


def _bind_task_creators(workflow, dag: DAG, prefix: str, *, include_dummy: bool = True):
    safe = _slug(prefix)

    def _op(task_id: str):
        return EmptyOperator(task_id=task_id, dag=dag)

    execute_op = _op("execute-job-cluster")
    workflow.execute_job_cluster_task_creator = MagicMock(return_value=execute_op)
    if include_dummy:
        workflow.dummy_job_cluster_finished_task_creator = MagicMock(
            return_value=_op("job-cluster-finished")
        )
    workflow.optimize_delta_table_task_creator = MagicMock(
        return_value=_op(f"optimize-{safe}")
    )
    workflow.load_query_task_creator = MagicMock(
        side_effect=lambda table: _op(f"load-{table.table_name}")
    )
    workflow.load_custom_task_creator = MagicMock(
        side_effect=lambda table: _op(f"load-custom-{table.table_name}")
    )
    workflow.register_delta_table_task_creator = MagicMock(
        side_effect=lambda table: _op(f"register-{table.table_name}")
    )
    workflow.sync_metadata_task_creator = MagicMock(
        side_effect=lambda table, *a, **k: _op(f"sync-{table.table_name}")
    )
    workflow.data_quality_tests_task_creator = MagicMock(
        side_effect=lambda table: _op(f"data-quality-{table.table_name}")
    )
    workflow.skip_run_task_creator = MagicMock(return_value=_op("skip-run"))


def _enter_dag_patches(stack: ExitStack) -> None:
    for patcher in _dag_patches():
        stack.enter_context(patcher)


def smoke_query_delta(workflow_cls, layer: LayerEnum, name: str) -> SmokeResult:
    try:
        with ExitStack() as stack:
            stack.enter_context(
                patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.FORNO})
            )
            stack.enter_context(_install_emr_plugin())
            _enter_dag_patches(stack)
            workflow = workflow_cls(
                DAG_ARGS,
                {
                    "type": "query_delta",
                    "layer": layer.value,
                    "custom_schema": "smoke",
                    "has_hive_sync": True,
                },
                EMR_CLUSTER,
            )
            workflow.config_service = _config_service_mock()
            dag = _new_dag(name)
            workflow.dag = dag
            _bind_task_creators(workflow, dag, name)
            table = _table(layer=layer)
            with patch.object(workflow, "_get_tables", return_value=[table]):
                with patch.object(
                    workflow, "_check_include_skip_run_task", return_value=False
                ):
                    built = workflow.build_dag()
            return _verify_dag(built, name)
    except Exception as exc:  # noqa: BLE001 — smoke harness
        return SmokeResult(workflow=name, status="FAIL", error=str(exc))


def smoke_query_delta_cluster_method(
    workflow_cls, layer: LayerEnum, name: str
) -> SmokeResult:
    """Exercise _set_dependencies (attach path) with a realistic accessory chain graph."""
    try:
        with (
            patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.FORNO}),
            _install_emr_plugin(),
        ):
            workflow = workflow_cls(
                DAG_ARGS,
                {
                    "type": "query_delta",
                    "layer": layer.value,
                    "custom_schema": "smoke",
                    "has_hive_sync": True,
                },
                EMR_CLUSTER,
            )
            workflow.config_service = _config_service_mock()
            dag = _new_dag(name)
            ctx = workflow._get_dag_execution_context(dag, "datalake-bucket")
            table = _table(layer=layer)
            safe = _slug(name)
            execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
            load = EmptyOperator(task_id=f"load-{table.table_name}", dag=dag)
            register = EmptyOperator(task_id=f"register-{table.table_name}", dag=dag)
            sync = EmptyOperator(task_id=f"sync-{table.table_name}", dag=dag)
            optimize = EmptyOperator(task_id=f"optimize-{safe}", dag=dag)
            finished = EmptyOperator(task_id="job-cluster-finished", dag=dag)
            load >> register >> sync >> optimize
            table_first_tasks = {table.table_name: load}
            table_last_tasks = {table.table_name: load}
            workflow._set_dependencies(
                execute,
                table_first_tasks,
                table_last_tasks,
                optimize,
                finished,
                ctx,
                execute_job_cluster_local_id=1,
            )
            return _verify_dag(dag, name)
    except Exception as exc:  # noqa: BLE001
        return SmokeResult(workflow=name, status="FAIL", error=str(exc))


def smoke_enrich_emr_validation_test() -> SmokeResult:
    """Load enrich_emr_validation_test via FactoryDispatcher + declaration dict."""
    try:
        from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
            FactoryDispatcher,
        )

        decl = {
            "dag": {
                "name": "enrich_emr_validation_test",
                "owner": "Data Life Cycle",
                "schedule_start_date": [2026, 1, 1],
            },
            "workflow": {
                "type": "query_delta",
                "layer": "enrich",
                "custom_schema": "emr_validation_test",
                "default_extraction_type": "full",
                "default_partitions": [],
            },
            "cluster": {"type": "emr_7_12_med_general_cluster"},
        }
        with ExitStack() as stack:
            stack.enter_context(
                patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.FORNO})
            )
            stack.enter_context(_install_emr_plugin())
            _enter_dag_patches(stack)
            with (
                patch.object(
                    DAGPackagesPathService,
                    "list_queries_files_in_composer",
                    return_value=["emr_validation"],
                ),
                patch(
                    "bietlejuice.base.service.file_service.FileService.read",
                    return_value="SELECT 1 AS id",
                ),
            ):
                factory = FactoryDispatcher(layer=LayerEnum.ENRICH).get_factory(
                    dag_conf=decl["dag"],
                    workflow_conf=decl["workflow"],
                    cluster_conf=decl["cluster"],
                )
                dag = factory.get_workflow().build_dag()
            return _verify_dag(dag, "enrich_emr_validation_test (real DAG)")
    except Exception as exc:  # noqa: BLE001
        return SmokeResult(
            workflow="enrich_emr_validation_test (real DAG)",
            status="FAIL",
            error=str(exc),
        )


def smoke_core_support_journey() -> SmokeResult:
    try:
        with (
            patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.FORNO}),
            _install_emr_plugin(),
        ):
            import importlib.util

            path = REPO_ROOT / "dags/core/core_support_journey/core_support_journey.py"
            spec = importlib.util.spec_from_file_location("core_support_journey", path)
            if spec is None or spec.loader is None:
                raise RuntimeError(f"cannot load {path}")
            mod = importlib.util.module_from_spec(spec)
            with patch(
                "bietlejuice.services.configuration_service.ConfigurationService",
                return_value=_config_service_mock(),
            ):
                spec.loader.exec_module(mod)
            dag = mod.dag
            return _verify_dag(dag, "core_support_journey (legacy Python DAG)")
    except Exception as exc:  # noqa: BLE001
        return SmokeResult(
            workflow="core_support_journey (legacy Python DAG)",
            status="FAIL",
            error=str(exc),
        )


def _print_report(results: List[SmokeResult]) -> int:
    print("=" * 72)
    print("EMR terminate-emr-cluster workflow smoke evidence")
    print("=" * 72)
    failures = 0
    for r in results:
        icon = {"PASS": "✓", "FAIL": "✗", "SKIP": "○"}.get(r.status, "?")
        print(f"\n{icon} [{r.status}] {r.workflow}")
        if r.error:
            print(f"    error: {r.error}")
        if r.execute_task_id:
            print(f"    execute: {r.execute_task_id}")
        if r.terminate_task_id:
            print(f"    terminate: {r.terminate_task_id}")
        if r.collected_work_tasks:
            print(
                f"    collected work tasks ({len(r.collected_work_tasks)}): {r.collected_work_tasks}"
            )
        if r.terminate_upstreams:
            print(
                f"    terminate upstreams ({len(r.terminate_upstreams)}): {r.terminate_upstreams}"
            )
        if r.accessory_upstreams:
            print(f"    accessory upstreams: {r.accessory_upstreams}")
        if r.missing_from_terminate:
            print(f"    MISSING from terminate: {r.missing_from_terminate}")
            failures += 1
        elif r.status == "FAIL":
            failures += 1
        elif r.status == "SKIP":
            print("    (skipped — workflow not EMR-routable in this harness)")

    print("\n" + "=" * 72)
    passed = sum(1 for r in results if r.status == "PASS")
    skipped = sum(1 for r in results if r.status == "SKIP")
    failed = sum(1 for r in results if r.status == "FAIL")
    print(
        f"Summary: {passed} passed, {failed} failed, {skipped} skipped / {len(results)} total"
    )
    print("=" * 72)

    report_path = REPO_ROOT / "local/emr_terminate_workflow_smoke_report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps([asdict(r) for r in results], indent=2),
        encoding="utf-8",
    )
    print(f"\nJSON report: {report_path}")
    return 1 if failures or failed else 0


def main() -> int:
    import subprocess

    cases = [
        ("query_delta_enrich", "enrich"),
        ("dw_query_delta_agent_contract", "dw_agent_contract"),
        ("dw_query_delta_agent_contract_databricks", "dw_agent_contract_databricks"),
        ("collector_synthetic", "collector"),
    ]
    results: List[SmokeResult] = []
    script = str(Path(__file__).resolve())
    for label, case in cases:
        proc = subprocess.run(
            [sys.executable, script, "--case", case],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
            env={**os.environ, "PYTHONPATH": ""},
        )
        if proc.stdout.strip():
            print(proc.stdout)
        if proc.returncode != 0 and proc.stderr.strip():
            print(proc.stderr, file=sys.stderr)
        child_report = REPO_ROOT / f"local/emr_terminate_smoke_{case}.json"
        if child_report.exists():
            data = json.loads(child_report.read_text(encoding="utf-8"))
            results.append(SmokeResult(**data))
        elif proc.returncode == 2:
            results.append(
                SmokeResult(workflow=label, status="FAIL", error=proc.stderr.strip())
            )

    if not results:
        return _run_case("collector")

    return _print_report(results)


def _run_case(case: str) -> int:
    if case == "enrich":
        result = smoke_query_delta_cluster_method(
            EnrichQueryDeltaWorkflow, LayerEnum.ENRICH, "query_delta_enrich"
        )
    elif case == "dw":
        result = smoke_query_delta_cluster_method(
            DwQueryDeltaWorkflow, LayerEnum.DW, "query_delta_dw"
        )
    elif case == "dw_agent_contract":
        result = smoke_dw_agent_contract_inner_deps()
    elif case == "dw_agent_contract_databricks":
        result = smoke_dw_agent_contract_databricks()
    else:
        result = _collector_synthetic_evidence()

    child_report = REPO_ROOT / f"local/emr_terminate_smoke_{case}.json"
    child_report.parent.mkdir(parents=True, exist_ok=True)
    child_report.write_text(json.dumps(asdict(result), indent=2), encoding="utf-8")

    icon = {"PASS": "✓", "FAIL": "✗", "SKIP": "○"}.get(result.status, "?")
    print(f"{icon} [{result.status}] {result.workflow}")
    if result.collected_work_tasks:
        print(f"    collected: {result.collected_work_tasks}")
    if result.terminate_upstreams:
        print(f"    terminate upstreams: {result.terminate_upstreams}")
    if result.accessory_upstreams:
        print(f"    accessories: {result.accessory_upstreams}")
    if result.missing_from_terminate:
        print(f"    MISSING: {result.missing_from_terminate}")
    if result.error:
        print(f"    error: {result.error}")
    return 1 if result.status == "FAIL" else 0


def _collector_synthetic_evidence() -> SmokeResult:
    """Printable evidence from the register-retry regression graph (unit-level)."""
    dag = DAG(
        dag_id="smoke_collector_synthetic",
        schedule=None,
        start_date=datetime(2026, 1, 1),
    )
    execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
    load = EmptyOperator(task_id="load", dag=dag)
    register = EmptyOperator(task_id="register", dag=dag)
    sync = EmptyOperator(task_id="sync", dag=dag)
    data_quality = EmptyOperator(task_id="data_quality", dag=dag)
    optimize = EmptyOperator(task_id="optimize", dag=dag)
    term = EmptyOperator(
        task_id="terminate-emr-cluster", dag=dag, trigger_rule="all_done"
    )
    EmptyOperator(task_id="job-cluster-finished", dag=dag)
    execute >> load >> register >> sync >> optimize >> term
    load >> data_quality >> optimize

    from bietlejuice.base.airflow.job_cluster_engine import (
        attach_emr_terminate_cluster_work_prerequisites,
    )
    from bietlejuice.base.airflow.task_creators.dag_execution_context import (
        DagExecutionContext,
    )

    ctx = DagExecutionContext(
        dag=dag,
        environment="forno",
        bucket="b",
        base_spark_jobs_path="/x/",
        dag_args={},
        workflow_args={},
        cluster_args=EMR_CLUSTER,
    )
    ctx.use_airflow_emr = True
    ctx.job_cluster_engine = MagicMock(uses_emr_terminate_after_optimize=True)
    attach_emr_terminate_cluster_work_prerequisites(
        ctx, term, execute_job_cluster_task=execute
    )
    return _verify_dag(dag, "collector_synthetic_register_sync_dq")


def smoke_dw_agent_contract_databricks() -> SmokeResult:
    """dw_agent_contract on Databricks cluster: no terminate task, no cycle."""
    name = "dw_query_delta_agent_contract_databricks"
    try:
        with (
            patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.FORNO}),
            _install_emr_plugin(),
        ):
            workflow = DwQueryDeltaWorkflow(
                {"name": "dw_agent_contract", "owner": "Data Agents"},
                {
                    "type": "query_delta",
                    "layer": "dw",
                    "custom_schema": "agent",
                    "default_extraction_type": "full",
                    "inner_dependencies": {
                        "fact_agent_contract": ["dim_work_contract"],
                        "fact_daily_accredited_agent": ["fact_agent_contract"],
                    },
                },
                {
                    "type": "consolidation_m_general_cluster",
                    "databricks_conn_id": "databricks_new_env",
                },
            )
            workflow.config_service = _config_service_mock()
            dag = _new_dag(name)
            ctx = workflow._get_dag_execution_context(dag, "dw-bucket")

            execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
            jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
            optimize = EmptyOperator(task_id=f"optimize-{_slug(name)}", dag=dag)

            dim_load = EmptyOperator(task_id="load-dim_work_contract", dag=dag)
            dim_add_default = EmptyOperator(
                task_id="add-default-dim_work_contract", dag=dag
            )
            fact_load = EmptyOperator(task_id="load-fact_agent_contract", dag=dag)
            daily_load = EmptyOperator(
                task_id="load-fact_daily_accredited_agent", dag=dag
            )

            table_first_tasks = {
                "dim_work_contract": dim_load,
                "fact_agent_contract": fact_load,
                "fact_daily_accredited_agent": daily_load,
            }
            table_last_tasks = {
                "dim_work_contract": dim_add_default,
                "fact_agent_contract": fact_load,
                "fact_daily_accredited_agent": daily_load,
            }

            workflow._set_dependencies(
                ctx,
                execute,
                table_first_tasks,
                table_last_tasks,
                optimize,
                jcf,
            )

            list(dag.topological_sort())
            if any(t.task_id.startswith("terminate-emr-cluster") for t in dag.tasks):
                return SmokeResult(
                    workflow=name,
                    status="FAIL",
                    error="Databricks DAG must not have terminate-emr-cluster",
                )
            return SmokeResult(
                workflow=name,
                status="SKIP",
                error="no terminate-emr-cluster on Databricks (expected)",
            )
    except Exception as exc:  # noqa: BLE001
        return SmokeResult(workflow=name, status="FAIL", error=str(exc))


def smoke_dw_agent_contract_inner_deps() -> SmokeResult:
    """dw_agent_contract-shaped graph: inner deps + register/sync + cycle check."""
    name = "dw_query_delta_agent_contract"
    try:
        with (
            patch.dict("os.environ", {"ENVIRONMENT": EnvironmentEnum.FORNO}),
            _install_emr_plugin(),
        ):
            workflow = DwQueryDeltaWorkflow(
                {"name": "dw_agent_contract", "owner": "Data Agents"},
                {
                    "type": "query_delta",
                    "layer": "dw",
                    "custom_schema": "agent",
                    "default_extraction_type": "full",
                    "inner_dependencies": {
                        "fact_agent_contract": ["dim_work_contract"],
                        "fact_daily_accredited_agent": ["fact_agent_contract"],
                    },
                },
                EMR_CLUSTER,
            )
            workflow.config_service = _config_service_mock()
            dag = _new_dag(name)
            ctx = workflow._get_dag_execution_context(dag, "dw-bucket")
            ctx.use_airflow_emr = True

            execute = EmptyOperator(task_id="execute-job-cluster", dag=dag)
            jcf = EmptyOperator(task_id="job-cluster-finished", dag=dag)
            optimize = EmptyOperator(task_id=f"optimize-{_slug(name)}", dag=dag)

            dim_load = EmptyOperator(task_id="load-dim_work_contract", dag=dag)
            dim_add_default = EmptyOperator(
                task_id="add-default-dim_work_contract", dag=dag
            )
            dim_register = EmptyOperator(task_id="register-dim_work_contract", dag=dag)
            dim_sync = EmptyOperator(task_id="sync-dim_work_contract", dag=dag)
            fact_load = EmptyOperator(task_id="load-fact_agent_contract", dag=dag)
            fact_register = EmptyOperator(
                task_id="register-fact_agent_contract", dag=dag
            )
            fact_sync = EmptyOperator(task_id="sync-fact_agent_contract", dag=dag)
            daily_load = EmptyOperator(
                task_id="load-fact_daily_accredited_agent", dag=dag
            )
            daily_register = EmptyOperator(
                task_id="register-fact_daily_accredited_agent", dag=dag
            )
            daily_sync = EmptyOperator(
                task_id="sync-fact_daily_accredited_agent", dag=dag
            )

            execute >> dim_load >> dim_add_default >> fact_load
            dim_load >> dim_register >> dim_sync >> optimize
            fact_load >> fact_register >> fact_sync >> optimize
            daily_load >> daily_register >> daily_sync >> optimize

            table_first_tasks = {
                "dim_work_contract": dim_load,
                "fact_agent_contract": fact_load,
                "fact_daily_accredited_agent": daily_load,
            }
            table_last_tasks = {
                "dim_work_contract": dim_add_default,
                "fact_agent_contract": fact_load,
                "fact_daily_accredited_agent": daily_load,
            }

            workflow._set_dependencies(
                ctx,
                execute,
                table_first_tasks,
                table_last_tasks,
                optimize,
                jcf,
            )

            list(dag.topological_sort())
            return _verify_dag(dag, name)
    except Exception as exc:  # noqa: BLE001
        return SmokeResult(workflow=name, status="FAIL", error=str(exc))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--case":
        raise SystemExit(_run_case(sys.argv[2]))
    raise SystemExit(main())
