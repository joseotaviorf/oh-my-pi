import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts import list_cluster_validation_eligible_dags as eligibility  # noqa: E402


class TestClassify:
    def test_phase1_query_delta(self):
        declaration = {
            "cluster": {"type": "databricks_16_4_med_general_cluster"},
            "workflow": {"type": "query_delta"},
        }

        assert eligibility.classify(declaration) == "phase1"

    def test_phase1_with_custom_spark_job(self):
        declaration = {
            "cluster": {"type": "databricks_16_4_med_general_cluster"},
            "workflow": {
                "type": "query_delta",
                "load_spark_job": "custom_job",
            },
        }

        assert (
            eligibility.classify(declaration) == "phase1_needs_allow_custom_spark_job"
        )

    def test_wonka_is_unsupported(self):
        declaration = {
            "cluster": {"type": "databricks_16_4_med_general_cluster"},
            "workflow": {"type": "wonka"},
        }

        assert eligibility.classify(declaration) == "unsupported"

    def test_skips_emr_cluster(self):
        declaration = {
            "cluster": {"type": "emr_default_cluster"},
            "workflow": {"type": "query_delta"},
        }

        assert eligibility.classify(declaration) is None

    def test_already_consolidation(self):
        declaration = {
            "cluster": {"type": "consolidation_s_general_single_node_cluster"},
            "workflow": {"type": "query_delta"},
        }

        assert eligibility.classify(declaration) == "already_consolidation"


class TestHasLoadSparkJob:
    def test_tables_customization_dict_guard(self):
        declaration = {
            "workflow": {
                "tables_customization": "not-a-dict",
            }
        }

        assert eligibility._has_load_spark_job(declaration) is False
