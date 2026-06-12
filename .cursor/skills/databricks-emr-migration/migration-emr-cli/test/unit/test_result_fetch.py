import json
from unittest.mock import MagicMock, patch

from emr.result_fetch import (
    fetch_json_from_s3,
    format_result_json_line,
    parse_result_json_line,
    split_s3_uri,
)


def test_split_s3_uri() -> None:
    bucket, key = split_s3_uri("s3://bucket/prefix/file.json")
    assert bucket == "bucket"
    assert key == "prefix/file.json"


def test_format_and_parse_result_json_line() -> None:
    payload = {"count": 7, "schema": []}
    line = format_result_json_line(payload)
    parsed = parse_result_json_line(f"noise\n{line}\n")
    assert parsed == payload


def test_fetch_json_from_s3() -> None:
    body = json.dumps({"count": 3}).encode("utf-8")
    with patch("emr.result_fetch.boto3.client") as mock_client:
        mock_client.return_value.get_object.return_value = {
            "Body": MagicMock(read=MagicMock(return_value=body))
        }
        payload = fetch_json_from_s3(
            "s3://bucket/emr/staging/cli/migration-validate/run/table.json",
            retries=1,
        )
    assert payload == {"count": 3}
