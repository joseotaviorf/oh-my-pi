import json

import pytest

from bietlejuice.base.airflow.optimize_delta_tables_cli import (
    EMR_TABLES_B64_PREFIX,
    decode_tables_config_from_cli,
    encode_tables_json_for_emr_cli,
)


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
