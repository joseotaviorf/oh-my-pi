import argparse
import glob
import os
import re
from os.path import join
from pathlib import Path

import pyaml

from sql_metadata import Parser

path = Path(__file__).absolute()
BIETLEJUICE_ROOT = path.parent.parent.parent.absolute()
DAG_PACKAGES_ROOT = join(BIETLEJUICE_ROOT, "dags")
DAY_COL_STRING = """day
"""


def create_yml_for_table(sql, database_name, table_name):
    sql_parser = Parser(sql)
    print(
        '{"vendor": ["atlas"],"database_name": "'
        + database_name
        + '", "table_name": "'
        + table_name
        + '"},'
    )
    yml_body = {"database_name": database_name, "table_name": table_name, "columns": {}}

    alias_columns = {}
    for alias, column in sql_parser.columns_aliases.items():
        if isinstance(column, list):
            if len(column) > 0:
                alias_columns[column[0]] = alias
        else:
            alias_columns[column] = alias

    if DAY_COL_STRING in sql and "day" not in sql_parser.columns:
        sql_parser._columns.extend(["day"])
    for column in sql_parser.columns:
        alias = alias_columns.get(column) or column
        yml_body["columns"][alias.lower()] = {
            "lineage": [f"{sql_parser.tables[0].lower()}.{column.lower()}"]
        }

    return yml_body


def save_yml(file_path, yml_body):
    filename = file_path.replace("/queries/", "/metadata/").replace(".sql", ".yml")

    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "w+") as f:
        pyaml.dump(yml_body, f, sort_keys=False, explicit_start=True)


if __name__ == "__main__":
    """
    To use the script, first run the following command:
    make requirements-scripts-python3
    """
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--folder", "-f", required=True, help="dag name folder")
    arg_parser.add_argument(
        "--table", "-t", help="Specific table to create the lineage"
    )

    args = arg_parser.parse_args()
    path = DAG_PACKAGES_ROOT

    dag_name_path = args.folder  # use "ebdb", "godfather", for instance
    table = args.table if args.table != None else "*"
    file_paths = list(
        glob.iglob(f"{path}/**/{dag_name_path}/**/{table}.sql", recursive=True)
    )
    if len(file_paths) == 0:
        print("No files found")

    for file_path in file_paths:
        if "/clean/" in file_path:
            layer = "clean"
        elif "/raw/" in file_path:
            layer = "raw"
        elif "/enrich/" in file_path:
            layer = "enrich"
        elif "/dw/" in file_path:
            layer = "dw"
        elif "/metric/" in file_path:
            layer = "metric"
        else:
            raise Exception(f"ERROR finding the layer.")
        regex = f"{path}(.*)\/(.*)\/queries\/(.*)\/(.*).sql"
        database_name = re.search(regex, file_path).group(2)
        table_name = re.search(regex, file_path).group(4)

        if layer in ("raw", "clean"):
            db_template = f"datalake_{database_name}_{layer}"
        elif layer == "enrich":
            database_name = database_name.replace("enrich_", "")
            db_template = f"datalake_{database_name}"
        elif layer == "dw":
            db_template = f"{database_name}"
        elif layer == "metric":
            db_template = f"{database_name}"

        with open(file_path, "r") as stream:
            sql = stream.read()
            try:
                yml_body = create_yml_for_table(sql, db_template, table_name)
                save_yml(file_path, yml_body)
            except Exception:
                print(f"ERROR database_name={database_name}, table_name={table_name}")
