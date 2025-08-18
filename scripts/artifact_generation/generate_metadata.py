import argparse
import glob
import os
import re
from os.path import join
from pathlib import Path

import yaml

from sqlglot import parse_one, exp

path = Path(__file__).absolute()
BIETLEJUICE_ROOT = path.parent.parent.parent.absolute()
DAG_PACKAGES_ROOT = join(BIETLEJUICE_ROOT, "dags")
DAY_COL_STRING = """day
"""


def create_yml_for_table(
    sql, database_name, table_name, sql_file_path, dag_owner=None, do_lineage=True
):
    # sql_parser = Parser(sql)
    print(
        f'{{"vendor": ["datahub"],"database_name": "{database_name}", "table_name": "{table_name}"}},'
    )
    dag_domain = None
    for domain in os.listdir(DAG_PACKAGES_ROOT):
        if domain in sql_file_path:
            dag_domain = domain
    yml_body = {
        "database_name": database_name,
        "table_name": table_name,
        "owner": dag_owner if dag_owner else None,
        "domain": dag_domain,
        "description": None,
        "columns": {},
    }

    sql_parser = parse_one(sql)
    for column in sql_parser.expressions:
        yml_body["columns"][column.output_name] = {"description": ""}
        if do_lineage: ## TODO review how to treat lineage for more complex cases
            first_table_name = sql_parser.find(exp.Table).db + "." + sql_parser.find(exp.Table).name
            yml_body["columns"][column.output_name].update(
                        {"lineage": [f"{first_table_name}.{column.this}"]}
                        )


    return yml_body


def save_yml(file_path, yml_body):
    filename = file_path.replace("/queries/", "/metadata/").replace(".sql", ".yml")

    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "w+") as f:
        yaml.dump(yml_body, f, sort_keys=False, explicit_start=True)


if __name__ == "__main__":
    """
    To use the script, first run the following command:
    make requirements-scripts
    """
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument("--folder", "-f", required=True, help="dag name folder")
    arg_parser.add_argument(
        "--table", "-t", help="Specific table to create the metadata"
    )
    arg_parser.add_argument("--owner", "-o", help="Owner email", required=False)
    arg_parser.add_argument(
        "--no-lineage",
        "-nl",
        help="Force script to do only descriptions",
        default=False,
        required=False,
        dest="no_lineage",
        action="store_true",
    )

    args = arg_parser.parse_args()
    path = DAG_PACKAGES_ROOT

    dag_name_path = args.folder  # use "ebdb", "godfather", for instance
    dag_owner = args.owner
    table = args.table if args.table != None else "*"
    do_lineage = False if args.no_lineage else True
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
        elif "/core/" in file_path:
            layer = "core"
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
        elif layer == "core":
            db_template = f"{database_name}"
        elif layer == "dw":
            db_template = f"{database_name}"
        elif layer == "metric":
            db_template = f"{database_name}"

        with open(file_path, "r") as stream:
            sql = stream.read().replace('`', '"')
            try:
                yml_body = create_yml_for_table(
                    sql, db_template, table_name, file_path, dag_owner, do_lineage
                )
                save_yml(file_path, yml_body)
            except Exception as e:
                print(e)
                print(f"ERROR database_name={database_name}, table_name={table_name}")
