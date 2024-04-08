import argparse
import glob
from typing import Tuple
import yaml
from os.path import join
from pathlib import Path
import re
import sys
import os

NOT_IDENTIFIED_TEXT = "<NOT IDENTIFIED, INFORM MANUALLY>"

path = Path(__file__).absolute()
BIETLEJUICE_ROOT = path.parent.parent.parent.absolute()
DAG_PACKAGES_ROOT = join(BIETLEJUICE_ROOT, "dags")
BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

def main(dag_name: str) -> None:
    dag_path, dag_file_content = read_dag_file(dag_name)
    conf_file = read_prod_conf_file(dag_name)
    dag_declaration = generate_dag_declaration(dag_name, dag_file_content, conf_file)
    write_to_dag_package(dag_path, dag_declaration)

def read_dag_file(dag_name: str) -> Tuple[str, str]:
    """Returns the full path of the dag file and its content"""

    dag_path = list(
        glob.iglob(f"{DAG_PACKAGES_ROOT}/**/{dag_name}/*.py", recursive=True)
    )[0]
    with open(dag_path, "r") as f:
        return dag_path, f.read()
    
def read_prod_conf_file(dag_name: str) -> dict:
    """Returns the content of the prod_conf.yml file in the DAG package, if it exists."""

    conf_paths = list(
        glob.iglob(f"{DAG_PACKAGES_ROOT}/**/{dag_name}/prod_conf.y*l", recursive=True)
    )
    if len(conf_paths) == 0:
        return None
    conf_path = conf_paths[0]
    with open(conf_path, "r") as f:
        return yaml.safe_load(f)
    
def read_markdown_file(dag_name: str) -> str:
    md_paths = list(
        glob.iglob(f"{DAG_PACKAGES_ROOT}/**/{dag_name}/*.md", recursive=True)
    )
    if len(md_paths) == 0:
        return None
    md_path = md_paths[0]
    with open(md_path, "r") as f:
        return f.read()
    
def generate_dag_declaration(dag_name: str, dag_file: str, conf_file: dict) -> dict:
    """Generates the content of the DAG declaration file"""

    return {
        "ATTENTION!": "This file was generated automatically. Please, check if the content is correct, then delete this key, the Python file and the other ymls. "
            "Pay special attention to custom schemas, which are not identified automatically, and table customizations, like partitions and extraction type. "
            "This is a template generator with a few automatic extractions, but you shouldn't fully trust it.",
        "dag": extract_dag_key_content_for_declaration(dag_name, dag_file, conf_file),
        "workflow": extract_workflow_key_content_for_declaration(dag_file, conf_file),
        "cluster": extract_cluster_key_content_for_declaration(dag_file, conf_file),
    }

def write_to_dag_package(dag_path: str, dag_declaration: dict) -> None:
    """Writes the DAG declaration to the DAG package"""
    
    declaration_path = dag_path.replace(".py", "_declaration.yml")

    with open(declaration_path, "w") as f:
        yaml.dump(dag_declaration, f, sort_keys=False, explicit_start=True)
    
def extract_dag_key_content_for_declaration(dag_name: str, dag_file: str, conf_file: dict) -> dict:
    """Extracts the content of the DAG key for the declaration file, using regexes in the python file and the config file"""

    start_date_pattern = r"START_DATE\s=\sdatetime\(\s*(?P<year>\d+)\s*,\s*(?P<month>\d+)\s*,\s*(?P<day>\d+)"
    start_date_match = re.search(start_date_pattern, dag_file, flags=re.IGNORECASE)
    start_date = f"{start_date_match.group('year')}, {start_date_match.group('month')}, {start_date_match.group('day')}"

    dag_owner_pattern = r"DAGOwnerEnum\.(\w+)"
    dag_owner_enum_str = re.search(dag_owner_pattern, dag_file).group(1)
    dag_owner = DAGOwnerEnum().__getattribute__(dag_owner_enum_str)

    content = {
        "name": dag_name,
        "schedule_start_date": start_date,
        "owner": dag_owner,
    }

    if conf_file and "dag_documentation" in conf_file:
        content["documentation"] = conf_file["dag_documentation"]
    else:
        content_from_md = extract_dag_documentation_from_md(dag_name)
        if content_from_md:
            content["documentation"] = {"dag_purpose": content_from_md} 

    return content


def extract_dag_documentation_from_md(dag_name: str) -> str:
    md_content = read_markdown_file(dag_name)
    if not md_content:
        return None
    # Anything between the ### Purpose and <details> tags
    documentation_match = re.search(r"### Purpose\s*([^<]*)<details>", md_content, flags=re.IGNORECASE)
    if not documentation_match:
        return None
    return documentation_match.group(1).replace("\u200B", "").strip() # Some documentation files have zero width spaces


def extract_workflow_key_content_for_declaration(dag_file: str, conf_file: dict) -> dict:
    """Extracts the content of the workflow key for the declaration file, using regexes in the python file and the config file"""

    content = {
        "type": "query",
        "layer": "enrich"
    }
    if conf_file and conf_file.get("inner_dependencies"):
        content["inner_dependencies"] = conf_file["inner_dependencies"]

    if re.search(r"is_incremental\s*=\s*True", dag_file):
        content["default_extraction_type"] = "incremental"
        content["default_partitions"] = ["year", "month", "day"]
    
    # Matches strings like
    # partition_cols = ["year", "month", "day"]
    # partitions = ["year", "month", "day"]
    partition_match_in_file = re.search(r"partition\w+\s*=\s*(\[(?:\"\w+\",?\s?)+\])", dag_file, flags=re.IGNORECASE)
    if partition_match_in_file:
        content["default_partitions"] = yaml.safe_load(partition_match_in_file.group(1))

    if conf_file and "partition_cols" in conf_file and isinstance(conf_file["partition_cols"], list):
        content["default_partitions"] = conf_file["partition_cols"]
    if conf_file and "partitions" in conf_file and isinstance(conf_file["partitions"], list):
        content["default_partitions"] = conf_file["partitions"]

    if "extra_query_template_params" in dag_file:
        content["extra_query_template_params"] = NOT_IDENTIFIED_TEXT

    tables_customization = extract_tables_customization(conf_file)
    if tables_customization:
        content["tables_customization"] = tables_customization

    return content

def extract_tables_customization(conf_file: dict) -> dict:
    """Extracts the content of the tables_customization key for the declaration file, using the config file"""

    tables_customization = {}
    if conf_file is None:
        return tables_customization
    
    # For when tables is a list in the format
    # tables:
    #   - table_name: table1
    #     is_incremental: True
    if "tables" in conf_file and isinstance(conf_file["tables"], list):
        for table in conf_file["tables"]:
            table_name = table["table_name"]
            tables_customization[table_name] = {}
            if table.get("is_incremental"):
                tables_customization[table_name]["extraction_type"] = "incremental"
            if "partitions" in table:
                tables_customization[table_name]["partitions"] = table["partitions"]
            if "partition_cols" in table:
                tables_customization[table_name]["partitions"] = table["partition_cols"]

    # For when tables is a dict in the format
    # tables:
    #   table1:
    #     is_incremental: True
    elif "tables" in conf_file and isinstance(conf_file["tables"], dict):
        for table_name, table in conf_file["tables"].items():
            tables_customization[table_name] = {}
            if table.get("is_incremental") in table:
                tables_customization[table_name]["extraction_type"] = "incremental"
            if "partitions" in table:
                tables_customization[table_name]["partitions"] = table["partitions"]
            if "partition_cols" in table:
                tables_customization[table_name]["partitions"] = table["partition_cols"]

    # For when partition_cols is a dict in the format
    # partition_cols:
    #   table1:
    #     - partition1
    if "partition_cols" in conf_file and isinstance(conf_file["partition_cols"], dict):
        for table_name, partition_cols in conf_file["partition_cols"].items():
            if table_name not in tables_customization:
                tables_customization[table_name] = {}
            tables_customization[table_name]["partitions"] = partition_cols

    # For when incremental_tables is a list in the format
    # incremental_tables:
    #   - table1
    for table_name in conf_file.get("incremental_tables", []):
        if table_name not in tables_customization:
            tables_customization[table_name] = {}
        tables_customization[table_name]["extraction_type"] = "incremental"

    # Delete tables that have no customization
    for table_name in list(tables_customization.keys()):
        if not tables_customization[table_name]:
            del tables_customization[table_name]

    return tables_customization

def extract_cluster_key_content_for_declaration(dag_file: str, conf_file: dict) -> dict:
    """Extracts the content of the cluster key for the declaration file, using regexes in the python file and the config file"""

    cluster_type_pattern = r"((?:databricks_\d|custom_cluster).*)(?:\"|')" 
    cluster_type_match = re.search(cluster_type_pattern, dag_file)
    cluster_type = cluster_type_match.group(1)
    content = {"type": cluster_type}
    if cluster_type == "custom_cluster":
        content["custom_configurations"] = conf_file["custom_cluster"]
    if conf_file and "spark_conf" in conf_file:
        if "custom_configurations" not in content:
            content["custom_configurations"] = {}
        content["custom_configurations"]["spark_conf"] = conf_file["spark_conf"]
    elif "spark_conf" in dag_file:
        if "custom_configurations" not in content:
            content["custom_configurations"] = {}
        content["custom_configurations"]["spark_conf"] = NOT_IDENTIFIED_TEXT

    return content

def parse_dag_name() -> str:
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--dag", "-d", required=True, help="dag name folder")
    args = arg_parser.parse_args()
    return args.dag

if __name__ == '__main__':
    dag_name = parse_dag_name()
    main(dag_name)
