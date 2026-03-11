from typing import List, Dict


def get_libs(env):
    # Match project convention: forno -> artifacts.s3.forno.data.*, prod -> artifacts.s3.data.*
    env_part = "forno.data" if env == "forno" else "data"
    artifact_bucket = f"artifacts.s3.{env_part}.quintoandar.com.br"
    return [
        {
            "whl": f"s3://{artifact_bucket}/bi-etl-ejuice/bi_etl_ejuice-latest-py3-none-any.whl"
        },
        {
            "whl": f"s3://{artifact_bucket}/python-logger/quintoandar_logger-0.8.0-py3-none-any.whl"
        },
    ]


def get_cluster_config(config_service):

    # TODO: Update here if we need additional spark configs
    cluster_config = config_service.get_config("custom_cluster")
    cluster_config["data_security_mode"] = "SINGLE_USER"
    cluster_config["single_user_name"] = "{{ var.value.databricks_single_user_name }}"
    cluster_config["spark_conf"][
        "spark.databricks.sql.initial.catalog.namespace"
    ] = "quintoandar_{{ var.value.environment }}"

    return cluster_config


def parse_parameters(parameters: Dict) -> List[str]:
    result = []
    for key, value in parameters.items():
        result.extend([f"--{key}", str(value)])
    return result
