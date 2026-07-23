"""CLI argument encoding for optimize_delta_table Spark job (EMR-safe).

Lives under base.airflow (not base.spark) so importing task creators does not
execute spark/__init__.py, which initializes PySpark and breaks Airflow DAG parsing.
"""

from __future__ import annotations

import base64
import json
from typing import Any, Callable, Dict, List, Sequence

# Prefix must stay in sync with OptimizeDeltaTableTaskCreator (EMR path only).
EMR_TABLES_B64_PREFIX = "B64:"

# AWS EMR HadoopJarStep.Args per-element length limit (each Args[i]).
EMR_HADOOP_JAR_STEP_ARG_ELEMENT_MAX_LENGTH = 10280

# Backward-compatible alias (older code/tests referenced this name).
EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH = EMR_HADOOP_JAR_STEP_ARG_ELEMENT_MAX_LENGTH

# AWS EMR AddJobFlowSteps: total character count of all HadoopJarStep string
# values (Jar + MainClass + Args + Properties) must not exceed 10,240.
# See: https://docs.aws.amazon.com/emr/latest/APIReference/API_AddJobFlowSteps.html
EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH = 10240

# Default Jar used by QuintoAndar EMR spark-submit steps (emr_plugin).
EMR_COMMAND_RUNNER_JAR = "command-runner.jar"

# Absolute spark-submit path used on EMR Amazon Linux (matches emr_plugin / emr-cli).
EMR_SPARK_SUBMIT_BIN = "/usr/lib/spark/bin/spark-submit"

# Baseline spark-submit --conf pairs always injected for optimize EMR steps.
# Keep in sync with EmrJobClusterEngine._build_emr_extra_spark_submit_args defaults
# (Delta + S3A ACL + SPARK_RUNTIME). Used only to size optimize batches.
_EMR_OPTIMIZE_BASELINE_SPARK_CONFS: tuple[str, ...] = (
    "--conf",
    "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension",
    "--conf",
    "spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog",
    "--conf",
    "spark.hadoop.fs.s3a.acl.default=BucketOwnerFullControl",
    "--conf",
    "spark.hadoop.fs.s3a.canned.acl=BucketOwnerFullControl",
    "--conf",
    "spark.yarn.appMasterEnv.SPARK_RUNTIME=emr",
    "--conf",
    "spark.driverEnv.SPARK_RUNTIME=emr",
    "--conf",
    "spark.openlineage.parentJobNamespace=airflow",
)

# Conservative fallback when script URI / OpenLineage task id are unknown at
# unit-test time. Prefer :func:`build_optimize_emr_hadoop_jar_step_args`.
EMR_OPTIMIZE_STEP_RESERVED_ARGS_TOTAL_LENGTH = 900


def encode_tables_json_for_emr_cli(tables_json: str) -> str:
    """Wrap JSON so EMR/YARN spark-submit does not split or mangle a multi-token string."""
    return EMR_TABLES_B64_PREFIX + base64.standard_b64encode(
        tables_json.encode("utf-8")
    ).decode("ascii")


def decode_tables_config_from_cli(tables_arg: str) -> Dict[str, Any]:
    """Inverse of encode_tables_json_for_emr_cli; accepts raw JSON (Databricks) or B64:… (EMR)."""
    stripped = tables_arg.strip()
    if stripped.startswith(EMR_TABLES_B64_PREFIX):
        raw = base64.standard_b64decode(
            stripped[len(EMR_TABLES_B64_PREFIX) :].encode("ascii")
        )
        return json.loads(raw.decode("utf-8"))
    return json.loads(stripped)


def hadoop_jar_step_string_values_total(
    *,
    jar: str,
    args: Sequence[str],
    main_class: str = "",
    properties: Sequence[tuple[str, str]] = (),
) -> int:
    """Total characters of all string values in a HadoopJarStep (AWS total budget)."""
    total = len(jar) + len(main_class)
    total += sum(len(str(arg)) for arg in args)
    for key, value in properties:
        total += len(str(key)) + len(str(value))
    return total


def validate_emr_hadoop_jar_step(
    *,
    jar: str = EMR_COMMAND_RUNNER_JAR,
    args: Sequence[str],
    main_class: str = "",
    properties: Sequence[tuple[str, str]] = (),
) -> None:
    """Validate EMR HadoopJarStep against AWS per-field and total string budgets."""
    total = hadoop_jar_step_string_values_total(
        jar=jar, args=args, main_class=main_class, properties=properties
    )
    if total > EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH:
        raise ValueError(
            "EMR HadoopJarStep exceeds AddJobFlowSteps total string budget "
            f"({total} > {EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH})"
        )
    for field_name, value in (
        ("Jar", jar),
        ("MainClass", main_class),
        *[(f"Args[{i}]", arg) for i, arg in enumerate(args)],
    ):
        if not value:
            continue
        value_len = len(str(value))
        if value_len > EMR_HADOOP_JAR_STEP_ARG_ELEMENT_MAX_LENGTH:
            raise ValueError(
                f"EMR HadoopJarStep {field_name} exceeds per-field budget "
                f"({value_len} > {EMR_HADOOP_JAR_STEP_ARG_ELEMENT_MAX_LENGTH})"
            )


# Backward-compatible name used by optimize task creator wiring.
def validate_emr_hadoop_jar_step_args(args: Sequence[str]) -> None:
    validate_emr_hadoop_jar_step(args=args)


def build_optimize_emr_hadoop_jar_step_args(
    *,
    script_uri: str,
    job_parameters: Sequence[Any],
    task_id: str,
    dag_id: str,
    deploy_mode: str = "client",
    extra_spark_args: Sequence[str] = (),
) -> List[str]:
    """Build HadoopJarStep Args for an optimize EMR spark-submit (validation only).

    Mirrors the layout used by emr_plugin ``build_spark_submit_step`` + optimize
    task wiring. Exists so optimize batching can budget the **full** step without
    changing general EMR submit paths.
    """
    openlineage_job = [
        "--conf",
        f"spark.openlineage.parentJobName={dag_id}.{task_id}",
    ]
    return [
        EMR_SPARK_SUBMIT_BIN,
        "--master",
        "yarn",
        "--deploy-mode",
        deploy_mode,
        *_EMR_OPTIMIZE_BASELINE_SPARK_CONFS,
        *openlineage_job,
        *extra_spark_args,
        script_uri,
        *[str(parameter) for parameter in job_parameters],
    ]


def make_optimize_emr_step_validator(
    *,
    script_uri: str,
    layer_value: str,
    parallelism: int,
    include_load_dates: bool,
    load_start_date: str,
    load_end_date: str,
    maintenance_cli_args: Sequence[str],
    task_id: str,
    dag_id: str,
    deploy_mode: str = "client",
    extra_spark_args: Sequence[str] = (),
) -> Callable[[str], None]:
    """Return a validate_step_fit(encoded_tables) for the full optimize EMR step."""

    def validate_step_fit(encoded_tables_arg: str) -> None:
        job_parameters: List[Any] = [layer_value, encoded_tables_arg, parallelism]
        if include_load_dates:
            job_parameters += [
                "--load-start-date",
                load_start_date,
                "--load-end-date",
                load_end_date,
            ]
        job_parameters.extend(maintenance_cli_args)
        step_args = build_optimize_emr_hadoop_jar_step_args(
            script_uri=script_uri,
            job_parameters=job_parameters,
            task_id=task_id,
            dag_id=dag_id,
            deploy_mode=deploy_mode,
            extra_spark_args=extra_spark_args,
        )
        validate_emr_hadoop_jar_step(args=step_args)

    return validate_step_fit


def make_reserved_overhead_emr_step_validator(
    reserved_args_total: int = EMR_OPTIMIZE_STEP_RESERVED_ARGS_TOTAL_LENGTH,
) -> Callable[[str], None]:
    """Validate encoded tables arg using a fixed spark-submit overhead estimate."""

    def validate_step_fit(encoded_tables_arg: str) -> None:
        if len(encoded_tables_arg) > EMR_HADOOP_JAR_STEP_ARG_ELEMENT_MAX_LENGTH:
            raise ValueError(
                "EMR HadoopJarStep Args element exceeds per-field budget "
                f"({len(encoded_tables_arg)} > "
                f"{EMR_HADOOP_JAR_STEP_ARG_ELEMENT_MAX_LENGTH})"
            )
        total = (
            len(EMR_COMMAND_RUNNER_JAR) + reserved_args_total + len(encoded_tables_arg)
        )
        if total > EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH:
            raise ValueError(
                "EMR HadoopJarStep exceeds AddJobFlowSteps total string budget "
                f"({total} > {EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH})"
            )

    return validate_step_fit


def _encode_and_roundtrip_validate_tables_config(
    tables_config: Dict[str, Any],
) -> str:
    tables_json = json.dumps(tables_config, separators=(",", ":"))
    encoded = encode_tables_json_for_emr_cli(tables_json)
    decoded = decode_tables_config_from_cli(encoded)
    if decoded != tables_config:
        raise ValueError("Encoded optimize tables config failed round-trip validation")
    return encoded


def validate_emr_optimize_tables_config(
    tables_config: Dict[str, Any],
    validate_step_fit: Callable[[str], None],
) -> str:
    """Encode tables config and validate it fits the full EMR optimize step."""
    encoded = _encode_and_roundtrip_validate_tables_config(tables_config)
    try:
        validate_step_fit(encoded)
    except ValueError as exc:
        table_names = ", ".join(sorted(tables_config))
        raise ValueError(
            "Encoded optimize tables config does not fit EMR AddJobFlowSteps "
            f"limits for tables: {table_names}"
        ) from exc
    return encoded


def build_and_validate_emr_tables_cli_arg(
    tables_config: Dict[str, Any],
    *,
    validate_step_fit: Callable[[str], None] | None = None,
) -> str:
    """Encode tables config for EMR optimize spark-submit and validate at DAG parse time.

    When ``validate_step_fit`` is omitted, uses a reserved spark-submit overhead
    estimate so unit tests still enforce the total HadoopJarStep budget.
    """
    fit = validate_step_fit or make_reserved_overhead_emr_step_validator()
    return validate_emr_optimize_tables_config(tables_config, fit)


def assert_optimize_batches_partition_tables(
    table_attributes: Sequence[Any],
    chunks: Sequence[Sequence[Any]],
) -> None:
    """Verify batching covers every table exactly once, in original order."""
    original_names = [table.table_name for table in table_attributes]
    batched_names: List[str] = []
    for chunk in chunks:
        batched_names.extend(table.table_name for table in chunk)
    if batched_names != original_names:
        raise ValueError(
            "Optimize table batching must partition tables without loss, "
            f"duplication, or reordering; expected {original_names!r}, "
            f"got {batched_names!r}"
        )


def _chunk_items(items: Sequence[Any], batch_size: int) -> List[List[Any]]:
    if batch_size < 1:
        raise ValueError("batch_size must be at least 1")
    return [list(items[i : i + batch_size]) for i in range(0, len(items), batch_size)]


def _all_fixed_batches_fit_emr_limit(
    table_attributes: Sequence[Any],
    batch_size: int,
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
    validate_step_fit: Callable[[str], None],
) -> bool:
    for chunk in _chunk_items(table_attributes, batch_size):
        try:
            validate_emr_optimize_tables_config(
                build_tables_config(chunk), validate_step_fit
            )
        except ValueError:
            return False
    return True


def _validate_single_table_emr_limit(
    table_attributes: Sequence[Any],
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
    validate_step_fit: Callable[[str], None],
) -> None:
    for table in table_attributes:
        tables_config = build_tables_config([table])
        try:
            validate_emr_optimize_tables_config(tables_config, validate_step_fit)
        except ValueError as exc:
            raise ValueError(
                f"Table {table.table_name!r} optimize config exceeds EMR step "
                "limits and cannot be batched"
            ) from exc


def max_tables_per_emr_optimize_batch(
    table_attributes: Sequence[Any],
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
    validate_step_fit: Callable[[str], None],
) -> int:
    """Return the largest fixed batch size where every equal-sized chunk fits.

    Per-table payload sizes vary, so validity is **not** monotonic in batch size
    (a failing size-2 boundary can disappear at size 3). Scan downward from ``n``
    instead of binary search. Prefer :func:`chunk_table_attributes_for_emr_limit`
    for EMR auto-batching — greedy packing minimizes steps.
    """
    n = len(table_attributes)
    if n == 0:
        return 1

    _validate_single_table_emr_limit(
        table_attributes, build_tables_config, validate_step_fit
    )

    for batch_size in range(n, 0, -1):
        if _all_fixed_batches_fit_emr_limit(
            table_attributes,
            batch_size,
            build_tables_config,
            validate_step_fit,
        ):
            return batch_size

    raise ValueError(
        "No EMR-safe optimize batch size found; at least one table exceeds "
        "the AddJobFlowSteps step limits"
    )


def chunk_table_attributes_for_emr_limit(
    table_attributes: Sequence[Any],
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
    validate_step_fit: Callable[[str], None],
) -> List[List[Any]]:
    """Greedy first-fit chunking: pack tables in order until the next one overflows."""
    if not table_attributes:
        return []

    _validate_single_table_emr_limit(
        table_attributes, build_tables_config, validate_step_fit
    )

    chunks: List[List[Any]] = []
    current: List[Any] = []

    for table in table_attributes:
        candidate = current + [table]
        try:
            validate_emr_optimize_tables_config(
                build_tables_config(candidate), validate_step_fit
            )
        except ValueError:
            if not current:
                raise ValueError(
                    f"Table {table.table_name!r} optimize config exceeds EMR step "
                    "limits and cannot be batched"
                ) from None
            chunks.append(current)
            current = [table]
            validate_emr_optimize_tables_config(
                build_tables_config(current), validate_step_fit
            )
        else:
            current = candidate

    if current:
        chunks.append(current)
    return chunks
