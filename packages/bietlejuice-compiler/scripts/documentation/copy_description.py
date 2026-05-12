import argparse
import glob
import yaml
import json

from os.path import join
from pathlib import Path
from typing import Tuple, Dict

path = Path(__file__).absolute()
BIETLEJUICE_ROOT = path.parent.parent.parent.absolute()
DAG_PACKAGES_ROOT = join(BIETLEJUICE_ROOT, "dags")

def main():
    origin_dag, origin_table, destination_dag, destination_table, is_forward = read_arguments()
    origin_metadata = read_metadata(origin_dag, origin_table)
    destination_metadata = read_metadata(destination_dag, destination_table)
    updated_metadata = copy_from_origin_to_destination(origin_metadata, destination_metadata, is_forward)
    write_metadata(destination_dag, destination_table, updated_metadata)

def read_arguments() -> Tuple[str, str, str, str]:
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--origin-dag", "-od", required=True, help="Origin DAG")
    arg_parser.add_argument("--origin-table", "-ot", required=True, help="Origin table")
    arg_parser.add_argument("--destination-dag", "-dd", required=True, help="Destination DAG")
    arg_parser.add_argument("--destination-table", "-dt", required=True, help="Destination table")
    arg_parser.add_argument("--is-forward", "-f", action="store_true", help="Is forward?", default=False)

    args = arg_parser.parse_args()
    return args.origin_dag, args.origin_table, args.destination_dag, args.destination_table, args.is_forward

def read_metadata(dag_name: str, table_name: str) -> Dict:
    metadata_path = list(
        glob.iglob(f"{DAG_PACKAGES_ROOT}/**/{dag_name}/metadata/**/{table_name}.y*ml", recursive=True)
    )[0]
    with open(metadata_path, "r") as f:
        return yaml.load(f, Loader=yaml.FullLoader)

def copy_from_origin_to_destination(origin_metadata: dict, destination_metadata: dict, is_forward: bool) -> None:
    # If it is forward, the lineage we need to look at is the destination
    metadata_to_look_at_lineage = destination_metadata if is_forward else origin_metadata
    other_metadata = origin_metadata if is_forward else destination_metadata

    for column_name, column_data in metadata_to_look_at_lineage["columns"].items():
        lineage_column = column_data.get("lineage", [])
        if not lineage_column:
            print(f"Column {lineage_column} has no lineage on destination table metadata")
            continue
        table_in_lineage, column_in_lineage = lineage_column[0].split(".")[-2:]
        if table_in_lineage == other_metadata['table_name']:
            origin_column_name = column_in_lineage if is_forward else column_name
            destination_column_name = column_name if is_forward else column_in_lineage
            destination_metadata = copy_description(origin_metadata, destination_metadata, origin_column_name, destination_column_name)
    return destination_metadata


def copy_description(origin_metadata: dict, destination_metadata: dict, origin_column_name: str, destination_column_name: str) -> Dict:
    try:
        description = origin_metadata["columns"][origin_column_name].get("description")
        if not description:
            print(f"There is no description to copy on origin table for column {origin_column_name}")
            return destination_metadata
        if origin_column_name not in origin_metadata["columns"]:
            print(f"Column {origin_column_name} does not exist on origin metadata.")
            return destination_metadata
        if destination_column_name not in destination_metadata["columns"]:
            destination_metadata["columns"][destination_column_name] = {}
        if "description" in destination_metadata["columns"][destination_column_name]:
            print(f"Description already exists for column {destination_column_name}")
            return destination_metadata
        if len(destination_metadata["columns"][destination_column_name]['lineage']) > 1:
            print(f"Column {destination_column_name} has more than 1 column on lineage. Check it manually.")
            # Skipping lineages with more than 1 column may avoid copying description from
            # calculated columns.
            return destination_metadata
        if "description" not in origin_metadata["columns"][origin_column_name]:
            print(f"Column {destination_column_name} has no description on origin table")
            return destination_metadata
    except KeyError:
        print(f"Key 'lineage' probably does not exist on destination metadata for column {destination_column_name}")

    print(f"Copying {origin_column_name} FROM {origin_metadata['table_name']} TO {destination_column_name} ON {destination_metadata['table_name']}")
    destination_metadata["columns"][destination_column_name].update({"description" : description})
    return destination_metadata


def write_metadata(dag_name: str, table_name: str, metadata: dict) -> None:
    metadata_path = list(
        glob.iglob(f"{DAG_PACKAGES_ROOT}/**/{dag_name}/metadata/**/{table_name}.y*ml", recursive=True)
    )[0]
    with open(metadata_path, "w") as f:
        yaml.safe_dump(data=metadata, stream=f, sort_keys=False, allow_unicode=True)
        f.close()


if __name__ == '__main__':
    main()
