import glob
import re
import os
import pyaml

from sql_metadata import Parser


def create_yml_for_table(sql, database_name, table_name):
    parser = Parser(sql)
    print('{"vendor": ["atlas"],"database_name": "' + database_name + '", "table_name": "' + table_name + '"},')
    yml_body = {"database_name": database_name,
                "table_name": table_name,
                "columns": {}
                }

    alias_columns = {}
    for alias, column in parser.columns_aliases.items():
        if isinstance(column, list):
            if len(column) > 0:
                alias_columns[column[0]] = alias
        else:
            alias_columns[column] = alias

    for column in parser.columns:
        alias = alias_columns.get(column) or column
        yml_body["columns"][alias.lower()] = {"lineage": [f"{parser.tables[0].lower()}.{column.lower()}"]}

    return yml_body


def save_yml(file_path, yml_body):
    filename = file_path.replace("/queries/", "/metadata/").replace(".sql", ".yml")

    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "w+") as f:
        pyaml.dump(yml_body, f, sort_keys=False)


if __name__ == "__main__":
    """
    To use the script, first run the following command:
    make requirements-scripts-python3
    """

    # adjust path to point to specific dag folder or leave it empty for all clean sql files
    dag_name_path = "gsheets"  # use "ebdb", "autodialer", for instance
    path = f"../bietlejuice/jobs/composer/db/datalake/queries/"

    for file_path in glob.iglob(f"{path}{dag_name_path}/**/*.sql", recursive=True):
        if "/clean/" in file_path:

            regex = f"{path}(.*)/clean(.*)/(.*).sql"
            database_name = re.search(regex, file_path).group(1)
            table_name = re.search(regex, file_path).group(3)

            with open(file_path, "r") as stream:
                sql = stream.read()
                try:
                    yml_body = create_yml_for_table(sql, f"datalake_{database_name}_clean",
                                                    table_name)
                    save_yml(file_path, yml_body)
                except Exception:
                    print(f"ERROR database_name={database_name}, table_name={table_name}")
