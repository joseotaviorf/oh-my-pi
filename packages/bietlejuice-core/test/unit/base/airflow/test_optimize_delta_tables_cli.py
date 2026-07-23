import json

import pytest

from bietlejuice.base.airflow.optimize_delta_tables_cli import (
    EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH,
    EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH,
    EMR_OPTIMIZE_STEP_RESERVED_ARGS_TOTAL_LENGTH,
    EMR_TABLES_B64_PREFIX,
    _all_fixed_batches_fit_emr_limit,
    assert_optimize_batches_partition_tables,
    build_and_validate_emr_tables_cli_arg,
    chunk_table_attributes_for_emr_limit,
    decode_tables_config_from_cli,
    encode_tables_json_for_emr_cli,
    make_reserved_overhead_emr_step_validator,
    max_tables_per_emr_optimize_batch,
    validate_emr_hadoop_jar_step,
)


class _TableStub:
    def __init__(self, table_name: str) -> None:
        self.table_name = table_name


def _pin_like_table_config(name: str, schema: str = "pin_core") -> dict:
    return {
        name: {
            "schema": schema,
            "vacuum_retention_hours": 168,
            "run_optimize": False,
            "optimize_frequency_days": 1,
            "run_vacuum": True,
            "vacuum_lite": True,
            "maintenance_once_per_day": True,
            "z_order_by": [],
        }
    }


def _merge_pin_like_configs(names: list[str]) -> dict:
    config = {}
    for name in names:
        config.update(_pin_like_table_config(name))
    return config


def _fit():
    return make_reserved_overhead_emr_step_validator()


def test_decode_round_trip_compact_json():
    payload = {"t1": {"schema": "s", "z_order_by": [], "run_optimize": True}}
    dumped = json.dumps(payload, separators=(",", ":"))
    encoded = encode_tables_json_for_emr_cli(dumped)
    assert encoded.startswith(EMR_TABLES_B64_PREFIX)
    assert decode_tables_config_from_cli(encoded) == payload


def test_decode_plain_json_without_prefix():
    payload = {"t1": {"schema": "s"}}
    dumped = json.dumps(payload)
    assert decode_tables_config_from_cli(dumped) == payload


def test_decode_strips_whitespace_around_plain_json():
    payload = {"a": 1}
    dumped = "  " + json.dumps(payload) + "  "
    assert decode_tables_config_from_cli(dumped) == payload


def test_decode_invalid_json_raises():
    with pytest.raises(json.JSONDecodeError):
        decode_tables_config_from_cli("not-json")


def test_build_and_validate_emr_tables_cli_arg_round_trips_pin_like_config():
    payload = _merge_pin_like_configs(["type", "salary", "person"])
    encoded = build_and_validate_emr_tables_cli_arg(payload)
    assert encoded.startswith(EMR_TABLES_B64_PREFIX)
    assert decode_tables_config_from_cli(encoded) == payload
    _fit()(encoded)


def test_build_and_validate_emr_tables_cli_arg_rejects_oversized_payload():
    huge_value = "x" * EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH
    payload = {"t1": {"schema": "s", "padding": huge_value}}
    with pytest.raises(ValueError, match="does not fit EMR AddJobFlowSteps"):
        build_and_validate_emr_tables_cli_arg(payload)


def test_validate_emr_hadoop_jar_step_rejects_total_over_budget():
    with pytest.raises(ValueError, match="total string budget"):
        validate_emr_hadoop_jar_step(
            args=["a" * (EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH // 2)] * 3
        )


def test_assert_optimize_batches_partition_tables_accepts_valid_chunks():
    tables = [_TableStub("a"), _TableStub("b"), _TableStub("c")]
    chunks = [tables[:2], tables[2:]]
    assert_optimize_batches_partition_tables(tables, chunks)


def test_assert_optimize_batches_partition_tables_rejects_missing_table():
    tables = [_TableStub("a"), _TableStub("b"), _TableStub("c")]
    chunks = [tables[:1], tables[2:]]
    with pytest.raises(ValueError, match="partition tables without loss"):
        assert_optimize_batches_partition_tables(tables, chunks)


def test_assert_optimize_batches_partition_tables_rejects_duplicate_table():
    tables = [_TableStub("a"), _TableStub("b")]
    chunks = [[tables[0], tables[0]]]
    with pytest.raises(ValueError, match="partition tables without loss"):
        assert_optimize_batches_partition_tables(tables, chunks)


def _encoded_length_for_padding(table_name: str, padding_len: int) -> int:
    config = {table_name: {"schema": "s", "padding": "x" * padding_len}}
    dumped = json.dumps(config, separators=(",", ":"))
    return len(encode_tables_json_for_emr_cli(dumped))


def _padding_for_encoded_length(table_name: str, target_len: int) -> int:
    lo, hi = 0, EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH * 2
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if _encoded_length_for_padding(table_name, mid) <= target_len:
            lo = mid
        else:
            hi = mid - 1
    return lo


def test_max_tables_per_emr_optimize_batch_non_monotonic_fixed_batch_sizes():
    """Batch size 2 can fail while 3 passes when chunk boundaries shift."""
    # Stay under reserved-overhead total budget (~9.3k tables arg).
    small = _padding_for_encoded_length("small", 400)
    medium = _padding_for_encoded_length("medium", 8_000)
    tail = _padding_for_encoded_length("tail", 1_500)
    tables = [_TableStub("a"), _TableStub("b"), _TableStub("c"), _TableStub("d")]
    padding_by_name = {"a": small, "b": small, "c": medium, "d": tail}

    def build_config(chunk):
        return {
            table.table_name: {
                "schema": "s",
                "padding": "x" * padding_by_name[table.table_name],
            }
            for table in chunk
        }

    # size-2 chunks: [a,b] ok, [c,d] overflows; size-3: [a,b,c] ok, [d] ok
    assert not _all_fixed_batches_fit_emr_limit(tables, 2, build_config, _fit())
    assert _all_fixed_batches_fit_emr_limit(tables, 3, build_config, _fit())
    assert max_tables_per_emr_optimize_batch(tables, build_config, _fit()) == 3


def test_chunk_table_attributes_for_emr_limit_greedy_packs_uneven_payloads():
    small = _padding_for_encoded_length("small", 400)
    medium = _padding_for_encoded_length("medium", 8_000)
    tail = _padding_for_encoded_length("tail", 1_500)
    tables = [_TableStub("a"), _TableStub("b"), _TableStub("c"), _TableStub("d")]
    padding_by_name = {"a": small, "b": small, "c": medium, "d": tail}

    def build_config(chunk):
        return {
            table.table_name: {
                "schema": "s",
                "padding": "x" * padding_by_name[table.table_name],
            }
            for table in chunk
        }

    chunks = chunk_table_attributes_for_emr_limit(tables, build_config, _fit())
    assert [[t.table_name for t in chunk] for chunk in chunks] == [
        ["a", "b", "c"],
        ["d"],
    ]
    assert_optimize_batches_partition_tables(tables, chunks)


def test_max_tables_per_emr_optimize_batch_returns_full_count_for_small_set():
    tables = [_TableStub(f"t{i}") for i in range(3)]

    def build_config(chunk):
        return _merge_pin_like_configs([t.table_name for t in chunk])

    assert max_tables_per_emr_optimize_batch(tables, build_config, _fit()) == 3


def test_max_tables_per_emr_optimize_batch_reduces_pin_like_74_table_set():
    tables = [_TableStub(f"table_{i}") for i in range(74)]

    def build_config(chunk):
        return _merge_pin_like_configs([t.table_name for t in chunk])

    batch_size = max_tables_per_emr_optimize_batch(tables, build_config, _fit())
    assert 1 < batch_size < 74
    chunks = [tables[i : i + batch_size] for i in range(0, len(tables), batch_size)]
    for chunk in chunks:
        encoded = build_and_validate_emr_tables_cli_arg(
            build_config(chunk), validate_step_fit=_fit()
        )
        _fit()(encoded)


def test_chunking_accounts_for_spark_submit_overhead_not_tables_alone():
    """Tables arg under per-field budget can still overflow total HadoopJarStep."""
    from bietlejuice.base.airflow.optimize_delta_tables_cli import (
        EMR_COMMAND_RUNNER_JAR,
    )

    max_encoded = (
        EMR_HADOOP_JAR_STEP_ARGS_TOTAL_MAX_LENGTH
        - EMR_OPTIMIZE_STEP_RESERVED_ARGS_TOTAL_LENGTH
        - len(EMR_COMMAND_RUNNER_JAR)
    )
    # Fits alone with a little headroom; pairing with another table overflows.
    big_padding = _padding_for_encoded_length("big", max_encoded - 80)
    small_padding = _padding_for_encoded_length("small", 200)
    tables = [_TableStub("big"), _TableStub("small")]

    def build_config(chunk):
        return {
            table.table_name: {
                "schema": "s",
                "padding": "x"
                * (big_padding if table.table_name == "big" else small_padding),
            }
            for table in chunk
        }

    assert build_and_validate_emr_tables_cli_arg(
        build_config([tables[0]]), validate_step_fit=_fit()
    )
    with pytest.raises(ValueError):
        build_and_validate_emr_tables_cli_arg(
            build_config(tables), validate_step_fit=_fit()
        )

    chunks = chunk_table_attributes_for_emr_limit(tables, build_config, _fit())
    assert [[t.table_name for t in chunk] for chunk in chunks] == [
        ["big"],
        ["small"],
    ]
    assert_optimize_batches_partition_tables(tables, chunks)


def test_make_optimize_emr_step_validator_rejects_when_full_step_over_budget():
    from bietlejuice.base.airflow.optimize_delta_tables_cli import (
        make_optimize_emr_step_validator,
    )

    padding = _padding_for_encoded_length("t", 10_000)
    payload = {
        "t": {
            "schema": "s",
            "padding": "x" * padding,
        }
    }
    validate = make_optimize_emr_step_validator(
        script_uri="s3://bucket/spark_jobs/base/optimize_delta_table.py",
        layer_value="clean",
        parallelism=16,
        include_load_dates=False,
        load_start_date="2026-01-01",
        load_end_date="2026-01-02",
        maintenance_cli_args=[
            "--environment",
            "prod",
            "--dag-name",
            "pin",
            "--maintenance-date",
            "2026-01-01",
        ],
        task_id="optimize-clean-all-batch-1",
        dag_id="pin",
    )
    with pytest.raises(ValueError, match="does not fit EMR AddJobFlowSteps"):
        build_and_validate_emr_tables_cli_arg(payload, validate_step_fit=validate)


def test_make_optimize_emr_step_validator_accepts_small_payload():
    from bietlejuice.base.airflow.optimize_delta_tables_cli import (
        make_optimize_emr_step_validator,
    )

    payload = _merge_pin_like_configs(["type", "salary"])
    validate = make_optimize_emr_step_validator(
        script_uri="s3://bucket/optimize_delta_table.py",
        layer_value="clean",
        parallelism=16,
        include_load_dates=False,
        load_start_date="2026-01-01",
        load_end_date="2026-01-02",
        maintenance_cli_args=[
            "--environment",
            "forno",
            "--dag-name",
            "pin",
            "--maintenance-date",
            "2026-01-01",
        ],
        task_id="optimize-clean-all",
        dag_id="pin",
    )
    encoded = build_and_validate_emr_tables_cli_arg(payload, validate_step_fit=validate)
    assert encoded.startswith(EMR_TABLES_B64_PREFIX)


def test_max_tables_per_emr_optimize_batch_names_oversized_single_table():
    tables = [_TableStub("only")]

    def build_config(chunk):
        return {
            chunk[0].table_name: {
                "schema": "s",
                "padding": "x" * EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH,
            }
        }

    with pytest.raises(ValueError, match="only.*exceeds EMR step"):
        max_tables_per_emr_optimize_batch(tables, build_config, _fit())
