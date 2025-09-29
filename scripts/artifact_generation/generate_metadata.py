"""
Script to generate metadata and lineage files (.yml) from SQL queries (.sql).

OVERVIEW:
This script automates table documentation by creating a .yml file for each .sql file.
It parses the query, extracts the column list, and traces the origin of each column (lineage),
even through multiple CTEs (WITH clauses).

REQUIREMENTS:
- make requirements-scripts

HOW TO USE:
Run the script from the command line, providing the necessary arguments.

MAIN ARGUMENTS:
  -f, --folder:   (Required) The name of the final DAG folder to be processed.
  -t, --table:    (Optional) The name of a specific table to generate metadata for.
                  If omitted, it processes all .sql files in the folder.
  -o, --owner:    (Optional) The owner's email to be inserted into the .yml file.
  -nl, --no-lineage: (Optional) Disables column-level lineage generation.

USAGE EXAMPLE:
# Generate metadata for the 'closing_rates' table in the 'currency' folder
python scripts/artifact_generation/generate_metadata.py -f currency -t closing_rates -o "your.name@quintoandar.com.br"

# Generate metadata for all tables in the 'currency' folder
python scripts/artifact_generation/generate_metadata.py -f currency -o "your.name@quintoandar.com.br"
"""

import argparse
import glob
import os
import re
from pathlib import Path

import yaml
from sqlglot import exp, parse_one


class LineageResolver:
    """
    An advanced lineage resolver capable of tracing the origin of columns
    through multiple CTEs (Common Table Expressions).

    Attributes:
        sql (str): The SQL query string to be parsed.
        expression (sqlglot.Expression): The query's syntax tree.
        ctes (dict): A dictionary mapping CTE names to their expressions.
    """

    def __init__(self, sql):
        """Initializes the resolver with the SQL query."""
        self.sql = sql
        self.expression = parse_one(sql, read="bigquery")
        self.ctes = {
            cte.alias_or_name: cte.this for cte in self.expression.find_all(exp.CTE)
        }

    def _map_aliases_in_scope(self, scope):
        """
        Maps all table and CTE aliases to their full names within a specific
        query scope (main query or a CTE).

        Args:
            scope (sqlglot.Expression): The query scope to be analyzed.

        Returns:
            dict: A dictionary mapping aliases to their source names.
                  The source can be a table name (str) or another CTE (Expression).
        """
        aliases = {}
        if scope.args.get("from"):
            for table in scope.args["from"].find_all(exp.Table):
                source_name = (
                    f"{table.db}.{table.name}"
                    if table.db
                    else self.ctes.get(table.name, table.name)
                )
                aliases[table.alias_or_name] = source_name

        for join in scope.args.get("joins", []):
            for table in join.find_all(exp.Table):
                source_name = (
                    f"{table.db}.{table.name}"
                    if table.db
                    else self.ctes.get(table.name, table.name)
                )
                aliases[table.alias_or_name] = source_name
        return aliases

    def trace(self, column_name, scope):
        """
        Recursively traces the origin of a column, navigating through
        CTEs until the source physical table is found.

        Args:
            column_name (str): The name (or alias) of the column to trace.
            scope (sqlglot.Expression): The current scope of the search.

        Returns:
            list[str]: A list of strings representing the column's sources
                       in the format "database.table.column".
        """
        source_expression = next(
            (expr for expr in scope.expressions if expr.alias_or_name == column_name),
            None,
        )
        if not source_expression:
            return []

        origins = []
        aliases_in_scope = self._map_aliases_in_scope(scope)

        for col_ref in source_expression.find_all(exp.Column):
            table_alias, col_name = col_ref.table, col_ref.name
            source = None

            if table_alias:
                source = aliases_in_scope.get(table_alias)
            elif len(aliases_in_scope) == 1:
                source = list(aliases_in_scope.values())[0]

            if isinstance(source, exp.Expression):  # The source is a CTE
                origins.extend(self.trace(col_name, source))
            elif isinstance(source, str):  # The source is a physical table
                origins.append(f"{source}.{col_name}")

        return list(set(origins))

    def get_lineage(self):
        """
        Orchestrates the lineage tracing for all columns in the final SELECT statement.

        Returns:
            dict: A dictionary mapping each column name to its origins.
                  Ex: {"my_column": {"lineage": ["db.table.source_col"]}}
        """
        final_query = self.expression.find(exp.Select)
        lineage_map = {}
        for col in final_query.expressions:
            col_alias = col.alias_or_name
            origins = self.trace(col_alias, final_query)
            if origins:
                lineage_map[col_alias] = {"lineage": origins}
        return lineage_map


def create_yml_for_table(
    sql, database_name, table_name, sql_file_path, dag_owner=None, do_lineage=True
):
    """
    Parses a SQL query to generate the metadata structure as a dictionary.

    Args:
        sql (str): The SQL query.
        database_name (str): The database name of the final table.
        table_name (str): The name of the final table.
        sql_file_path (str): The path to the original .sql file.
        dag_owner (str, optional): The DAG owner's email.
        do_lineage (bool, optional): If True, performs lineage analysis.

    Returns:
        dict: A dictionary containing the metadata ready to be saved as YAML.
    """
    print(
        f"Processing: database='{database_name}', table='{table_name}' from {sql_file_path}"
    )

    dag_domain = None
    try:
        path_parts = Path(sql_file_path).parts
        dag_root_index = path_parts.index("dags")
        if dag_root_index + 1 < len(path_parts):
            dag_domain = path_parts[dag_root_index + 1].capitalize()
    except ValueError:
        print("Warning: Could not determine domain from path.")

    yml_body = {
        "database_name": database_name,
        "table_name": table_name,
        "owner": dag_owner,
        "domain": dag_domain,
        "description": "",
        "columns": {},
    }

    sql_parser = parse_one(sql, read="bigquery")
    for column in sql_parser.expressions:
        yml_body["columns"][column.alias_or_name] = {"description": ""}

    if do_lineage:
        try:
            resolver = LineageResolver(sql)
            lineage_map = resolver.get_lineage()
            for col_name, data in lineage_map.items():
                if col_name in yml_body["columns"]:
                    yml_body["columns"][col_name].update(data)
        except Exception as e:
            print(f"  -> Error generating lineage for {table_name}: {e}")

    return yml_body


def save_yml(file_path, yml_body):
    """
    Saves a dictionary as a YAML file with custom formatting.

    Args:
        file_path (str): The path of the source .sql file.
        yml_body (dict): The metadata dictionary to be saved.
    """

    class IndentListsDumper(yaml.SafeDumper):
        def increase_indent(self, flow=False, indentless=False):
            return super(IndentListsDumper, self).increase_indent(flow, False)

    filename = file_path.replace("/queries/", "/metadata/").replace(".sql", ".yml")
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, "w+") as f:
        yaml.dump(
            yml_body,
            f,
            Dumper=IndentListsDumper,
            sort_keys=False,
            explicit_start=True,
            indent=2,
        )
    print(f"Metadata successfully saved to: {filename}")


def get_database_name(layer, db_from_path):
    """
    Determines the final database name based on the data layer.

    Args:
        layer (str): The data layer (e.g., 'clean', 'core').
        db_from_path (str): The database name extracted from the file path.

    Returns:
        str: The final, formatted database name.
    """
    layer_templates = {
        "raw": f"datalake_{db_from_path}_{layer}",
        "clean": f"datalake_{db_from_path}_{layer}",
        "enrich": f"datalake_{db_from_path.replace('enrich_', '')}",
        "core": db_from_path,
        "dw": db_from_path,
        "metric": db_from_path,
    }
    return layer_templates.get(layer)


if __name__ == "__main__":
    arg_parser = argparse.ArgumentParser(
        description="Generates YAML metadata files from SQL queries."
    )
    arg_parser.add_argument(
        "--dags-root",
        default=str(Path(__file__).parent.parent.parent.absolute() / "dags"),
        help="The root directory where DAG packages are stored.",
    )
    arg_parser.add_argument(
        "--folder", "-f", required=True, help="DAG folder to be scanned for SQL files."
    )
    arg_parser.add_argument(
        "--table", "-t", help="Specific table to create metadata for."
    )
    arg_parser.add_argument("--owner", "-o", help="Owner's email", required=False)
    arg_parser.add_argument(
        "--no-lineage",
        "-nl",
        help="Disables column-level lineage generation.",
        default=True,
        dest="do_lineage",
        action="store_false",
    )

    args = arg_parser.parse_args()
    dags_root_path = args.dags_root
    dag_name_path = args.folder
    dag_owner = args.owner
    table_pattern = args.table if args.table else "*"
    search_path = f"{dags_root_path}/**/{dag_name_path}/**/{table_pattern}.sql"
    file_paths = list(glob.iglob(search_path, recursive=True))

    if not file_paths:
        print(f"No files found for pattern: {search_path}")

    for file_path in file_paths:
        try:
            path_str = str(file_path)
            layer_match = re.search(
                r"/queries/((raw|clean|enrich|dw|metric|core))/", path_str
            )
            if not layer_match:
                print(f"Skipping file, could not determine layer: {file_path}")
                continue
            layer = layer_match.group(1)

            regex = f"{re.escape(dags_root_path)}/(.*)/(.*)/queries/(.*)/(.*).sql"
            match = re.search(regex, path_str)
            if not match:
                print(
                    f"Skipping file, path does not match expected structure: {file_path}"
                )
                continue

            database_from_path = match.group(2)
            table_name = match.group(4)
            final_database_name = get_database_name(layer, database_from_path)
            if not final_database_name:
                raise Exception(
                    f"ERROR finding database template for layer '{layer}'."
                )

            with open(file_path, "r") as stream:
                sql = stream.read().replace("`", '"')
                yml_body = create_yml_for_table(
                    sql,
                    final_database_name,
                    table_name,
                    file_path,
                    dag_owner,
                    args.do_lineage,
                )
                save_yml(file_path, yml_body)

        except Exception as e:
            print(f"\n--- ERROR processing file: {file_path} ---")
            print(f"Error details: {e}\n")
