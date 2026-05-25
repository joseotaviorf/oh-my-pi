import os
import sys

BI_ETL_EJUICE_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
sys.path.append(BI_ETL_EJUICE_ROOT)

import argparse
import datetime
import re
import textwrap
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Tuple, Union

import yaml

from bietlejuice.base.db.metastore_mapping_factory import MetastoreMappingFactory
from bietlejuice.base.pipeline import LayerEnum

TARGET_LAYERS = ["raw", "clean", "enrich", "dw"]
HARDCODED_SOURCE = "bietlejuice"

TITLE_MAP = {
    "raw": "{dag_name} (raw)",
    "clean": "{dag_name} (clean)",
    "enrich": "Enrich {dag_name}",
    "dw": "DW {dag_name}",
}

DESCRIPTION_MAP = {
    "raw": "Raw data from {dag_name} source system.",
    "clean": "Cleaned and standardized data from {dag_name}.",
    "enrich": "Enriched {dag_name} data with processed business logic and standardized relationships.",
    "dw": "Data warehouse layer for {dag_name} dimensional model.",
}


def parse_arguments() -> Dict[str, str]:
    """Parses command-line arguments and returns a configuration dictionary."""
    parser = argparse.ArgumentParser(
        description="Generate unified data contracts from DAG source structure.",
        formatter_class=argparse.RawTextHelpFormatter,
    )

    parser.add_argument(
        "--path-dags",
        type=str,
        default="dags",
        help="Path to the root DAGs directory OR a single *_declaration file.",
        required=True,
    )
    parser.add_argument(
        "--domain",
        type=str,
        required=True,
        help="Data Domain for the declared dags path. In case of any doubts, check the repository data-contracts",
    )
    parser.add_argument(
        "--subdomain",
        type=str,
        required=True,
        help="Data SubDomain for the declared dags path. In case of any doubts, check the repository data-contracts",
    )
    parser.add_argument(
        "--environment",
        type=str,
        default="forno",
        help="Target environment (e.g., 'forno', 'prod'). Used in IDs and paths (default: 'forno').",
    )
    parser.add_argument(
        "--creator-email",
        type=str,
        required=True,
        help="Email address of the contract creator",
    )

    parser.add_argument(
        "--output-path",
        type=str,
        default="contracts/{environment}/data_contracts",
        help="Output directory template (default: 'contracts/{environment}/data_contracts').",
    )
    parser.add_argument(
        "--catalog-name",
        type=str,
        default="quintoandar_{environment}",
        help="Databricks catalog name template (default: 'quintoandar_{environment}').",
    )

    args = parser.parse_args()

    config = vars(args)

    if "{environment}" not in config["output_path"]:
        print(
            "WARNING: output_path does not contain '{environment}'. It might not be environment-specific."
        )

    return config


def clean_prefix(name: str, prefixes: List[str]) -> str:
    for prefix in prefixes:
        if name.startswith(prefix):
            return name[len(prefix) :]
    return name


def clean_suffix(name: str, suffix: str) -> str:
    if name.endswith(suffix):
        return name[: -len(suffix)]
    return name


def get_dag_metadata_from_file(declaration_path: Path) -> Union[Dict[str, Any], None]:
    """Extracts global metadata from the _declaration.yml file."""
    try:
        with open(declaration_path, encoding="utf-8") as f:
            data = yaml.safe_load(f)

        if not data:
            print(f"READING ERROR: Empty declaration file at {declaration_path}.")
            return None

        dag_info = data.get("dag", {})
        workflow_info = data.get("workflow", {})

        dag_name_stem = clean_suffix(declaration_path.stem, "_declaration")

        return {
            "name": dag_info.get("name", dag_name_stem),
            "description": dag_info.get("dag_documentation", {}).get("dag_purpose", ""),
            "owner": dag_info.get("owner", "Unknown"),
            "custom_schema": workflow_info.get("custom_schema", None),
            "tables_customization": workflow_info.get("tables_customization", {}),
        }
    except yaml.YAMLError as e:
        print(f"Error: invalid YAML in {declaration_path}. {e}")
        return None
    except Exception as e:
        print(f"Error: {e}")
        return None


def extract_raw_table_name(columns_data: Dict[str, Any]) -> Union[str, None]:
    """
    Parses column lineage to find the raw table name used as the source.
    Assumes lineage format: <database>.<raw_table_name>.<column_name>
    """
    if not columns_data:
        return None

    first_column_data = next(iter(columns_data.values()), {})
    lineage_list = first_column_data.get("lineage", [])

    if not lineage_list:
        return None

    lineage_entry = lineage_list[0]

    match = re.match(r"[^.]+\.([^.]+)\.[^.]+", lineage_entry)
    if match:
        return match.group(1)

    return None


def find_and_extract_table_metadata(
    dag_path: Path, table_name: str, target_layer: str
) -> Dict[str, Any]:
    """Searches the metadata/layer/table_name.yml file to extract description, PII, and lineage."""
    metadata_dir = dag_path.parent / "metadata" / target_layer
    metadata_file_yml = metadata_dir / f"{table_name}.yml"
    metadata_file_yaml = metadata_dir / f"{table_name}.yaml"

    metadata_file = None
    if metadata_file_yml.exists():
        metadata_file = metadata_file_yml
    elif metadata_file_yaml.exists():
        metadata_file = metadata_file_yaml

    metadata_result = {
        "hasPII": "<FILL ME!>",
        "description": table_name,
        "lineage_raw_table": None,
    }

    if not metadata_file:
        return metadata_result

    try:
        metadata_content_str = metadata_file.read_text(encoding="utf-8")

        if "PII" in metadata_content_str.upper():
            metadata_result["hasPII"] = True

        metadata_data = yaml.safe_load(metadata_content_str)

        description_from_file = metadata_data.get("description")
        if description_from_file:
            metadata_result["description"] = description_from_file.strip()

        columns_data = metadata_data.get("columns", {})
        metadata_result["lineage_raw_table"] = extract_raw_table_name(columns_data)

    except yaml.YAMLError as e:
        print(f"Invalid metadata at {metadata_file}. Error: {e}")
    except Exception as e:
        print(f"Error while reading {metadata_file}: {e}")

    return metadata_result


def find_and_extract_all_tables_by_schema(
    dag_path: Path,
    target_layer: str,
    tables_customization: Dict,
    default_custom_schema: str,
) -> Dict[str, List[Tuple[str, Dict[str, Any]]]]:
    """
    Lists all tables based on .sql files and tables_customization, applies the
    custom_schema, extracts metadata, and returns a dict grouped by custom_schema.


    Retorns:
        Dict[str, List[Tuple[str, Dict[str, Any]]]]:
        Example:
        {custom_schema: [(table_name, metadata), (table_name_2, metadata_2), ...]}
    """

    queries_dir = dag_path.parent / "queries" / target_layer
    table_to_schema_map: Dict[str, str] = {}

    schemas_dict = defaultdict(list)
    processed_table_names = set()

    for query_file in queries_dir.glob("*.sql"):
        table_name = query_file.stem.lower()
        if table_name not in processed_table_names:
            table_to_schema_map[table_name] = default_custom_schema
            processed_table_names.add(table_name)

    for table, customization in tables_customization.items():
        final_table_name = customization.get("clean_table_name", table).lower()
        table_custom_schema = customization.get("custom_schema", default_custom_schema)

        table_to_schema_map[final_table_name] = table_custom_schema
        processed_table_names.add(final_table_name)

    for table_name, custom_schema in table_to_schema_map.items():
        metadata = find_and_extract_table_metadata(dag_path, table_name, target_layer)

        if metadata.get("description") or metadata.get("hasPII") is not None:
            schemas_dict[custom_schema].append((table_name, metadata))

    return schemas_dict


def generate_data_contract(
    config: Dict[str, str],
    dag_metadata: Dict[str, Any],
    layer: str,
    tables_data: List[Tuple[str, Dict[str, Any]]],
    custom_schema: str,
) -> str:
    dag_name = dag_metadata["name"]
    environment = config["environment"]
    domain = config["domain"]
    subdomain = config["subdomain"]

    schema_root = custom_schema or dag_name
    metastore_mapping = MetastoreMappingFactory.get_mapper_by_layer(
        LayerEnum(layer), schema_root, ""
    )
    schema_name = metastore_mapping.get_full_database_name(LayerEnum(layer))

    title = TITLE_MAP[layer].format(dag_name=dag_name.replace("_", " ").title())
    description = DESCRIPTION_MAP[layer].format(
        dag_name=dag_name.replace("_", " ").title()
    )

    if dag_metadata["description"]:
        description = description + " " + dag_metadata["description"]

    description = textwrap.indent(description, "    ").lstrip()

    domain_5a = f"{environment}-{domain}-domain"
    subdomain_5a = f"{environment}-{subdomain}-subdomain"

    team_owner_dynamic = f"{environment}-{subdomain}-data-team"

    timestamp = (
        datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
    )

    tables_yaml = ""
    for table_name, metadata in tables_data:
        has_pii = str(metadata.get("hasPII", False)).lower()
        description_table = metadata.get("description", table_name)

        indented_description = textwrap.indent(description_table.strip(), "      ")

        tables_yaml += f"""
  {table_name}:
    status: active
    type: table
    hasPII: {has_pii}
    description: |
{indented_description}
"""
    tables_yaml = tables_yaml.lstrip("\n")

    template = f"""dataContractSpecification: 1.1.0
id: urn:datacontract:{environment}:{subdomain}:{subdomain}:{HARDCODED_SOURCE}:{dag_name}:{dag_name}_{layer}
info:
  title: {title}
  version: 1.0.0
  description: |
    {description}
  owner: {team_owner_dynamic}
  status: active
  5ADomain: {domain_5a}
  5ASubdomain: {subdomain_5a}

5AMetadata:
  createdBy: {config["creator_email"]}
  createdAt: "{timestamp}"
  updatedBy: {config["creator_email"]}
  updatedAt: "{timestamp}"

models:
{tables_yaml}

servers:
  databricks:
    type: databricks
    catalog: {config["catalog_name"].format(environment=environment)}
    schema: {schema_name}
"""
    return template


def write_contract_file(
    config: Dict[str, str],
    dag_name: str,
    layer: str,
    yaml_content: str,
    custom_schema: str = None,
) -> None:
    """Helper function to write the contract file to the correct location."""
    domain = config["domain"]
    subdomain = config["subdomain"]
    output_path_formatted = config["output_path"].format(
        environment=config["environment"]
    )
    output_dir = (
        Path(output_path_formatted) / domain / subdomain / HARDCODED_SOURCE / dag_name
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    if custom_schema:
        output_file = output_dir / f"{dag_name}_{custom_schema}_{layer}.yaml"
    else:
        output_file = output_dir / f"{dag_name}_{layer}.yaml"
    output_file.write_text(yaml_content, encoding="utf-8")

    try:
        print(
            f"    -> Contract '{layer}' created at: {output_file.relative_to(Path.cwd())}"
        )
    except ValueError:
        print(f"    -> Contract '{layer}' created at: {output_file}")


def process_raw_contract_from_clean(
    config: Dict[str, str],
    dag_metadata: Dict[str, Any],
    clean_tables_data_by_schema: Dict[str, List[Tuple[str, Dict[str, Any]]]],
):
    """
    Generates the RAW layer contract, using CLEAN layer lineage to determine
    raw table names, creating one contract file per custom_schema.
    """
    dag_name = dag_metadata["name"]
    raw_layer = "raw"

    print(f"    -> Generating {raw_layer} contracts from CLEAN data...")

    for custom_schema, clean_tables_list in clean_tables_data_by_schema.items():
        raw_tables_data: List[Tuple[str, Dict[str, Any]]] = []

        for clean_table_name, metadata in clean_tables_list:
            raw_table_name = metadata.get("lineage_raw_table")
            if not raw_table_name:
                raw_table_name = clean_table_name

            raw_metadata = {
                "hasPII": metadata.get("hasPII"),
                "description": f"Raw data ingestion for {clean_table_name} (Source table: {raw_table_name}).",
            }

            raw_tables_data.append((raw_table_name, raw_metadata))

        if not raw_tables_data:
            print(
                f"        WARNING: No valid raw tables to process for schema: {custom_schema}."
            )
            continue

        raw_yaml_content = generate_data_contract(
            config, dag_metadata, raw_layer, raw_tables_data, custom_schema
        )

        write_contract_file(
            config, dag_name, raw_layer, raw_yaml_content, custom_schema
        )
        print(f"        -> RAW contract generated for schema: {custom_schema}")


def process_single_dag(config: Dict[str, str], declaration_path: Path):
    """
    Processes a single DAG definition file, extracts table metadata per layer,
    and generates data contracts grouped by custom schema.

    The contract generation is executed once for each unique custom_schema found
    within a target layer, using the aggregated list of tables and their metadata.

    Args:
        config (Dict[str, str]): Configuration settings for contract generation.
        declaration_path (Path): Path to the DAG declaration file.
    """

    dag_metadata = get_dag_metadata_from_file(declaration_path)
    if not dag_metadata:
        return

    dag_name_original = dag_metadata["name"]
    dag_name = dag_metadata["name"]
    dag_name = clean_prefix(dag_name, ["enrich_", "dw_", "metric_"])

    dag_metadata["name"] = dag_name

    print(f"\n[DAG: {dag_name_original} -> {dag_name}]")

    clean_tables_data_by_schema = defaultdict(list)

    for layer in TARGET_LAYERS:
        metadata_exist = (declaration_path.parent / "metadata" / layer).is_dir()
        query_exist = (declaration_path.parent / "queries" / layer).is_dir()
        if not (metadata_exist or query_exist):
            print(f"  - Skipping Layer '{layer}'. No metadata or query files found")
            continue

        print(f"  - Layer '{layer}'. Searching for tables...")
        schemas_dict = find_and_extract_all_tables_by_schema(
            declaration_path,
            layer,
            dag_metadata["tables_customization"],
            dag_metadata["custom_schema"],
        )

        if not schemas_dict:
            print(
                f"    WARNING: No valid tables found in '{layer}' layer. Contract not generated."
            )
            continue

        if layer == "clean":
            clean_tables_data_by_schema = schemas_dict

        for custom_schema, tables_data_list in schemas_dict.items():
            yaml_content = generate_data_contract(
                config, dag_metadata, layer, tables_data_list, custom_schema
            )

            write_contract_file(config, dag_name, layer, yaml_content, custom_schema)

    if clean_tables_data_by_schema:
        raw_metadata_exist = (declaration_path.parent / "metadata" / "raw").is_dir()
        if not raw_metadata_exist:
            print("  - Clean layer detected and no primary RAW metadata found.")
            process_raw_contract_from_clean(
                config, dag_metadata, clean_tables_data_by_schema
            )


def walk_dags_folder(root_dir: str = "dags") -> List[Path]:
    print(f"Searching for declaration files in '{root_dir}/**/*_declaration.yml'...")

    found_files = list(Path(root_dir).rglob("*_declaration.yml"))

    return list(set(found_files))


def main():

    config = parse_arguments()
    path_input = Path(config["path_dags"])
    output_root = Path(config["output_path"].format(environment=config["environment"]))

    if path_input.is_file():
        if not path_input.name.endswith(
            "_declaration.yml"
        ) and not path_input.name.endswith("_declaration.yaml"):
            print(
                f"FATAL ERROR: The specified file '{path_input}' is not a *_declaration.yml or *_declaration.yaml file."
            )
            return
        dag_declaration_files = [path_input]
        print(f"Processing single file mode: {path_input.name}")

    elif path_input.is_dir():
        dag_declaration_files = walk_dags_folder(config["path_dags"])
        print(f"Processing recursive directory mode from: {path_input}")
    else:
        print(
            f"FATAL ERROR: The specified path '{path_input}' does not exist or is neither a file nor a directory."
        )
        return

    if not dag_declaration_files:
        print(f"WARNING: No DAG declarations found in {path_input}.")
        return

    total_dags = len(dag_declaration_files)
    print("\n--- Unified Data Contract Process ---")
    print(f"Found {total_dags} DAG declarations to process.")

    for declaration_path in dag_declaration_files:
        try:
            try:
                log_path = declaration_path.relative_to(path_input)
            except ValueError:
                log_path = declaration_path.name

            print(f"Processing DAG: {log_path}")
            process_single_dag(config, declaration_path)
        except Exception as e:
            print(
                f"UNEXPECTED ERROR (main loop) while processing {declaration_path}: {e}"
            )

    print("\n--- Processing Complete ---")
    if output_root.exists():
        print(f"Verify generated contracts at: {output_root.resolve()}")


if __name__ == "__main__":
    main()
