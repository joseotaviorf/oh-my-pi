"""Unit tests for LakeFormationTagger EMR LF-tag ensure behavior."""

import os
from unittest.mock import MagicMock, patch

import pytest

from bietlejuice.base.spark.lake_formation_tagger import LakeFormationTagger


@pytest.fixture(autouse=True)
def reset_ensured_databases():
    LakeFormationTagger._ensured_databases = set()
    yield
    LakeFormationTagger._ensured_databases = set()


def _glue_client_with_lf(mock_lf):
    from bietlejuice.clients.db_clients.glue_client import GlueClient

    real = GlueClient(role_arn=None)
    real._lf = mock_lf
    real._glue = MagicMock()
    return real


class TestLakeFormationTagger:
    @patch.dict(os.environ, {"SPARK_RUNTIME": "emr"}, clear=False)
    @patch(
        "bietlejuice.base.spark.lake_formation_tagger.GlueCatalogHelper.get_glue_client"
    )
    def test_emr_missing_tag_stamps_unknown(self, mock_get_client):
        mock_lf = MagicMock()
        mock_lf.get_resource_lf_tags.return_value = {"LFTagOnDatabase": []}
        mock_lf.add_lf_tags_to_resource.return_value = {"Failures": []}
        mock_get_client.return_value = _glue_client_with_lf(mock_lf)

        LakeFormationTagger.ensure_database_data_contract_tag("agentic_platform")

        mock_lf.get_resource_lf_tags.assert_called_once_with(
            Resource={"Database": {"Name": "agentic_platform"}},
            ShowAssignedLFTags=True,
        )
        mock_lf.add_lf_tags_to_resource.assert_called_once_with(
            Resource={"Database": {"Name": "agentic_platform"}},
            LFTags=[{"TagKey": "data_contract_managed", "TagValues": ["unknown"]}],
        )
        assert "agentic_platform" in LakeFormationTagger._ensured_databases

    @pytest.mark.parametrize("existing_value", ["true", "false"])
    @patch.dict(os.environ, {"SPARK_RUNTIME": "emr"}, clear=False)
    @patch(
        "bietlejuice.base.spark.lake_formation_tagger.GlueCatalogHelper.get_glue_client"
    )
    def test_emr_existing_tag_not_overwritten(self, mock_get_client, existing_value):
        mock_lf = MagicMock()
        mock_lf.get_resource_lf_tags.return_value = {
            "LFTagOnDatabase": [
                {
                    "TagKey": "data_contract_managed",
                    "TagValues": [existing_value],
                }
            ]
        }
        mock_get_client.return_value = _glue_client_with_lf(mock_lf)

        LakeFormationTagger.ensure_database_data_contract_tag("bi_metrics")

        mock_lf.get_resource_lf_tags.assert_called_once()
        mock_lf.add_lf_tags_to_resource.assert_not_called()
        assert "bi_metrics" in LakeFormationTagger._ensured_databases

    @pytest.mark.parametrize(
        "env",
        [
            {},
            {"SPARK_RUNTIME": "databricks"},
        ],
    )
    @patch(
        "bietlejuice.base.spark.lake_formation_tagger.GlueCatalogHelper.get_glue_client"
    )
    def test_non_emr_is_noop(self, mock_get_client, env):
        with patch.dict(os.environ, env, clear=False):
            if "SPARK_RUNTIME" not in env:
                os.environ.pop("SPARK_RUNTIME", None)
            LakeFormationTagger.ensure_database_data_contract_tag("some_db")

        mock_get_client.assert_not_called()

    @patch.dict(os.environ, {"SPARK_RUNTIME": "emr"}, clear=False)
    @patch("bietlejuice.base.spark.lake_formation_tagger.logger.warning")
    @patch(
        "bietlejuice.base.spark.lake_formation_tagger.GlueCatalogHelper.get_glue_client"
    )
    def test_get_resource_lf_tags_failure_is_fail_open(
        self, mock_get_client, mock_warning
    ):
        mock_lf = MagicMock()
        mock_lf.get_resource_lf_tags.side_effect = RuntimeError("lf down")
        mock_get_client.return_value = _glue_client_with_lf(mock_lf)

        LakeFormationTagger.ensure_database_data_contract_tag("fragile_db")

        mock_lf.add_lf_tags_to_resource.assert_not_called()
        mock_warning.assert_called_once()
        assert "fragile_db" not in LakeFormationTagger._ensured_databases

    @patch.dict(os.environ, {"SPARK_RUNTIME": "emr"}, clear=False)
    @patch(
        "bietlejuice.base.spark.lake_formation_tagger.GlueCatalogHelper.get_glue_client"
    )
    def test_second_call_uses_cache(self, mock_get_client):
        mock_lf = MagicMock()
        mock_lf.get_resource_lf_tags.return_value = {"LFTagOnDatabase": []}
        mock_lf.add_lf_tags_to_resource.return_value = {"Failures": []}
        mock_get_client.return_value = _glue_client_with_lf(mock_lf)

        LakeFormationTagger.ensure_database_data_contract_tag("cached_db")
        LakeFormationTagger.ensure_database_data_contract_tag("cached_db")

        assert mock_lf.get_resource_lf_tags.call_count == 1
        assert mock_lf.add_lf_tags_to_resource.call_count == 1

    @patch.dict(os.environ, {"SPARK_RUNTIME": "emr"}, clear=False)
    @patch("bietlejuice.base.spark.lake_formation_tagger.logger.warning")
    @patch(
        "bietlejuice.base.spark.lake_formation_tagger.GlueCatalogHelper.get_glue_client"
    )
    def test_add_lf_tags_failures_are_fail_open_and_not_cached(
        self, mock_get_client, mock_warning
    ):
        mock_lf = MagicMock()
        mock_lf.get_resource_lf_tags.return_value = {"LFTagOnDatabase": []}
        mock_lf.add_lf_tags_to_resource.return_value = {
            "Failures": [
                {
                    "Error": {
                        "ErrorCode": "AccessDeniedException",
                        "ErrorMessage": "not authorized",
                    }
                }
            ]
        }
        mock_get_client.return_value = _glue_client_with_lf(mock_lf)

        LakeFormationTagger.ensure_database_data_contract_tag("rejected_db")

        mock_warning.assert_called_once()
        assert "rejected_db" not in LakeFormationTagger._ensured_databases

        # A later call must retry because the rejected stamp was not cached.
        LakeFormationTagger.ensure_database_data_contract_tag("rejected_db")
        assert mock_lf.add_lf_tags_to_resource.call_count == 2
