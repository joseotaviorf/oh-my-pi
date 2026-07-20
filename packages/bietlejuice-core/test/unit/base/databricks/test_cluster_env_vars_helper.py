import re
from pathlib import Path

from bietlejuice.base.databricks.cluster_env_vars_helper import ClusterEnvVarsHelper

_REPO_ROOT = Path(__file__).resolve().parents[6]
_EMR_INIT_SCRIPT = (
    _REPO_ROOT / "packages/bietlejuice-compiler/scripts/emr_init_script.sh"
)


def test_spark_3_5_uses_inmetro_4_11_0():
    assert ClusterEnvVarsHelper.get_inmetro_version("3.5") == "4.11.0"


def test_spark_3_2_keeps_legacy_inmetro_version():
    assert ClusterEnvVarsHelper.get_inmetro_version("3.2") == "2.3.0"


def test_input_emr_yarn_env_vars_injects_inmetro_from_spark_version_map():
    cluster_configuration = {
        "emr_configurations": [
            {
                "Classification": "yarn-env",
                "Configurations": [
                    {
                        "Classification": "export",
                        "Properties": {
                            "SPARK_VERSION": "3.5",
                            "SPARK_RUNTIME": "emr",
                        },
                    }
                ],
                "Properties": {},
            }
        ]
    }

    updated = ClusterEnvVarsHelper.input_emr_yarn_env_vars(cluster_configuration)
    props = updated["emr_configurations"][0]["Configurations"][0]["Properties"]

    assert props["INMETRO_VERSION"] == "4.11.0"
    assert props["DEEQU_JAR_VERSION"] == ClusterEnvVarsHelper.get_deequ_version("3.5")
    assert props["SPARK_VERSION"] == "3.5"


def test_input_emr_yarn_env_vars_defaults_spark_version_to_3_5():
    cluster_configuration = {
        "emr_configurations": [
            {
                "Classification": "yarn-env",
                "Configurations": [
                    {"Classification": "export", "Properties": {}},
                ],
                "Properties": {},
            }
        ]
    }

    updated = ClusterEnvVarsHelper.input_emr_yarn_env_vars(cluster_configuration)
    props = updated["emr_configurations"][0]["Configurations"][0]["Properties"]

    assert props["INMETRO_VERSION"] == ClusterEnvVarsHelper.get_inmetro_version("3.5")


def test_emr_init_script_inmetro_default_matches_spark_3_5_map():
    """Bootstrap cannot see yarn-env; script default must stay locked to the map."""
    script = _EMR_INIT_SCRIPT.read_text(encoding="utf-8")
    match = re.search(
        r'INMETRO_VERSION="\$\{INMETRO_VERSION:-([^}]+)\}"',
        script,
    )
    assert match, "INMETRO_VERSION default not found in emr_init_script.sh"
    assert match.group(1) == ClusterEnvVarsHelper.get_inmetro_version("3.5")
