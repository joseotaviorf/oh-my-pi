"""
This script can be used to generate one or many data-documentation base yml structure from documented lineages.
The result will not be a **complete** data-documentation structure, as there are optional tags to be complete, as *joins_with_column* and *category*, for example.
Also we do not generate the *categories* files under `database_name/categories` as this should be optional, but really stimulated.

Some use cases will be shown here:
1. Generate for one table:
    python generate_data_documentation_from_lineage.py --dag_folder "airtable" --table "activated"
2. Generate for all tables from one DAG:
    python generate_data_documentation_from_lineage.py --dag_folder airtable --table "*"
3. Generate for all DAGs:
    python generate_data_documentation_from_lineage.py --dag_folder "*" --table "*"
4. Generate for all DAGs on DW layer:
    python generate_data_documentation_from_lineage.py --dag_folder "dw_*" --table "*"
"""

import argparse
import pathlib
import glob
import os

import yaml
import pyaml

SCRIPTPATH = pathlib.Path(__file__).parent.resolve()


def create_yml_for_table(yaml_dict, database_name, table_name):
    yml_body = {
        "database_name": database_name,
        "name": table_name,
        "description": "",
        "owner": "",
        "columns": {},
    }

    columns = yaml_dict["columns"].keys()

    columns = {column: {"description": ""} for column in columns}

    yml_body["columns"] = columns

    return yml_body


def save_yml(database_name, table_name, yml_body):
    filepath = f"{SCRIPTPATH}/data-documentation/documentation/atlas/{database_name}/"
    filename = f"{filepath}/{table_name}.yml"

    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filename, "w+") as f:
        pyaml.dump(yml_body, f, sort_keys=False, explicit_start=True)


if __name__ == "__main__":
    """
    To use the script, first run the following command:
    make requirements-scripts-python3
    """
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument(
        "--dag_folder",
        "-f",
        required=True,
        help="Dag name folder. Can receive any glob pattern too, so if you want all dags, use '*'",
    )
    arg_parser.add_argument(
        "--table",
        "-t",
        help="Specific table to create the lineage. Can receive any glob pattern too, so if you want all tables for the dag, use '*'",
    )

    args = arg_parser.parse_args()
    path = f"{SCRIPTPATH}/../../bietlejuice/db/datalake/metadata/"

    dag_name_path = args.dag_folder  # use "ebdb", "godfather", for instance
    table = args.table if args.table != None else "*"

    paths_found = list(
        glob.iglob(f"{path}{dag_name_path}/**/{table}.yml", recursive=True)
    )
    if len(paths_found) == 0:
        print(
            f"ERROR: No paths were found for this glob expression: {path}{dag_name_path}/**/{table}.yml"
        )
    for file_path in paths_found:
        print(file_path)
        with open(file_path, "r") as f:
            lineage = yaml.safe_load(f)
            database = lineage["database_name"]
            table = lineage["table_name"]

            try:
                yml_body = create_yml_for_table(lineage, database, table)
                save_yml(database, table, yml_body)
            except Exception as e:
                print(f"ERROR database_name={database}, table_name={table}; Error= {e}")
