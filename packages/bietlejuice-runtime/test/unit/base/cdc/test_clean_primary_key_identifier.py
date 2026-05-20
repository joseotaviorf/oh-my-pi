from unittest import mock

from botocore.exceptions import ClientError

from bietlejuice.base.cdc.primary_key_identifiers.clean_primary_key_identifier import (
    CleanPrimaryKeyIdentifier,
)

_NOT_FOUND = ClientError(
    {"Error": {"Code": "NoSuchKey", "Message": "Not found"}},
    "GetObject",
)

_SAMPLE_METADATA = """
database_name: datalake_big_agent_clean
table_name: house
columns:
  id:
    lineage:
      - datalake_big_agent_raw.house.id
"""


@mock.patch(
    "bietlejuice.base.cdc.primary_key_identifiers.clean_primary_key_identifier.boto3"
)
@mock.patch(
    "bietlejuice.base.cdc.primary_key_identifiers.clean_primary_key_identifier.RuntimeDetector"
)
def test_read_table_metadata_uses_s3_on_emr(mock_runtime_detector, mock_boto3):
    mock_runtime_detector.is_emr.return_value = True
    mock_body = mock.Mock()
    mock_body.read.return_value = _SAMPLE_METADATA.encode("utf-8")
    mock_boto3.resource.return_value.Object.return_value.get.return_value = {
        "Body": mock_body
    }

    identifier = CleanPrimaryKeyIdentifier.__new__(CleanPrimaryKeyIdentifier)
    identifier.data_documentation_bucket = "data-documentation.s3.test.example"
    identifier.data_documentation_volume_path = "/Volumes/test/default/doc"
    identifier.spark = None

    metadata = identifier._read_table_metadata("big_agent", "house")

    assert metadata["table_name"] == "house"
    mock_boto3.resource.return_value.Object.assert_called_once_with(
        identifier.data_documentation_bucket,
        "metadata/datalake_big_agent_clean/house.yml",
    )


@mock.patch(
    "bietlejuice.base.cdc.primary_key_identifiers.clean_primary_key_identifier.boto3"
)
@mock.patch(
    "bietlejuice.base.cdc.primary_key_identifiers.clean_primary_key_identifier.RuntimeDetector"
)
def test_read_table_metadata_uses_s3_yaml_on_emr_when_yml_missing(
    mock_runtime_detector, mock_boto3
):
    mock_runtime_detector.is_emr.return_value = True
    mock_body = mock.Mock()
    mock_body.read.return_value = _SAMPLE_METADATA.encode("utf-8")

    def object_factory(bucket, key):
        mock_object = mock.Mock()
        if key.endswith(".yml"):
            mock_object.get.side_effect = _NOT_FOUND
        else:
            mock_object.get.return_value = {"Body": mock_body}
        return mock_object

    mock_boto3.resource.return_value.Object.side_effect = object_factory

    identifier = CleanPrimaryKeyIdentifier.__new__(CleanPrimaryKeyIdentifier)
    identifier.data_documentation_bucket = "data-documentation.s3.test.example"
    identifier.data_documentation_volume_path = "/Volumes/test/default/doc"
    identifier.spark = None

    metadata = identifier._read_table_metadata("big_agent", "house")

    assert metadata["table_name"] == "house"
    mock_boto3.resource.return_value.Object.assert_any_call(
        identifier.data_documentation_bucket,
        "metadata/datalake_big_agent_clean/house.yaml",
    )
