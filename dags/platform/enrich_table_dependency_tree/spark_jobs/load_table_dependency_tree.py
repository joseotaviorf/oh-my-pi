import argparse
import json
import pyspark.sql.functions as F
from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.spark import BaseSparkContext
from bietlejuice.loaders.delta_loader import DeltaLoader
from collections import deque
from datetime import datetime
from pyspark.sql import DataFrame
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    IntegerType,
)


def main() -> None:
    args = parse_args()
    execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d")
    dependencies = read_direct_dependencies_table(
        args.dependencies_table_name, execution_date
    )
    direct_and_indirect_dependencies = get_all_direct_and_indirect_dependencies_df(
        dependencies
    ).withColumns(
        {
            "year": F.lit(execution_date.year),
            "month": F.lit(execution_date.month),
            "day": F.lit(execution_date.day),
        }
    )
    load_table(
        direct_and_indirect_dependencies,
        args.env,
        args.bucket,
        args.schema,
        args.table_name,
        json.loads(args.partitions),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("bucket", type=str, help="bucket name")
    parser.add_argument("schema", type=str, help="schema of the table to be saved")
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument(
        "partitions", type=str, help="JSON string with list of partitions"
    )
    parser.add_argument(
        "execution_date", type=str, help="execution date in format YYYY-MM-DD"
    )
    parser.add_argument(
        "dependencies_table_name",
        type=str,
        help="Full name of the table that contains the dependencies between bietlejuice tables",
    )
    return parser.parse_args()


def read_direct_dependencies_table(
    dependencies_table_name: str, execution_date: datetime
) -> DataFrame:
    return BaseSparkContext.spark.table(dependencies_table_name).filter(
        f"year = {execution_date.year} and month = {execution_date.month} and day = {execution_date.day}"
    )


def get_all_direct_and_indirect_dependencies_df(dependencies: DataFrame) -> DataFrame:
    """
    Returns a dataframe mapping each dependent to a dependency, and the level.
    Level 1 = direct dependency
    Level > 1 = indirect dependency
    """

    graph, tables = create_graph(dependencies)
    dependency_rows = get_all_direct_and_indirect_dependencies_rows(graph, tables)
    return BaseSparkContext.spark.createDataFrame(
        dependency_rows,
        schema=StructType(
            [
                StructField("dependent_table_name", StringType(), False),
                StructField("dependency_table_name", StringType(), False),
                StructField("level", IntegerType(), False),
            ]
        )
    )


def get_all_direct_and_indirect_dependencies_rows(
    graph: list[list[int]], tables: list[str]
) -> list[tuple[str, str, int]]:
    """
    Returns a list of rows, each row being a tuple containing
    - dependent_table_name
    - dependency_table_name
    - level (1 for direct dependency, > 1 for indirect dependency)
    """

    dependency_rows = []
    for dependent_table_index in range(len(graph)):
        distance_map_with_indexes = breadth_first_search(graph, dependent_table_index)
        distance_map_with_names = translate_distance_map(
            tables, distance_map_with_indexes
        )
        for dependency, level in distance_map_with_names.items():
            dependency_rows.append((tables[dependent_table_index], dependency, level))
    return dependency_rows


def create_graph(dependencies: DataFrame) -> tuple[list[list[int]], list[str]]:
    """
    Returns a tuple containing
    - The adjacency lists of the graph
    - A list of table names in the same order as the adjacency list
    """

    # Collect? What a crime! But why not use Spark, you may ask?
    # What we want is to get all the pairs of nodes (tables) that are either directly or indirectly associated with
    # (dependent on) each other. I see two ways to do this
    # - Floyd-warshall, which is O(V^3). Not viable, since our graph is sparse and large
    # - Breadth first search for each node, which is O(V * (V+E)), or since E is in the same order of V, O(Vˆ2)
    # It would be pretty much impossible to do something similar efficiently with Spark, since it doesn't
    # have recursive CTEs. Since our data volume is relatively low, it ended up being much faster to do it like this.
    dependency_rows = dependencies.collect()
    tables = []
    table_indexes = {}
    graph = []

    def get_table_index(table_name: str) -> int:
        if table_name not in table_indexes:
            table_indexes[table_name] = len(table_indexes)
            tables.append(table_name)
            graph.append([])
        return table_indexes[table_name]

    for row in dependency_rows:
        dependent_table_name = row.dependent_table_name
        dependency_table_name = row.dependency_table_name
        dependent_table_index = get_table_index(dependent_table_name)
        dependency_table_index = get_table_index(dependency_table_name)
        graph[dependent_table_index].append(dependency_table_index)

    return graph, tables


def breadth_first_search(graph: list[list[int]], start: int) -> dict[int, int]:
    """
    BFS.
    Given the adjacency list and the start index, returns a dictionary mapping each node to its distance from the start node
    """

    distances = {}
    visited = set()

    queue = deque([start])
    visited.add(start)
    level = 0
    while queue:
        nodes_in_level = len(queue)
        while nodes_in_level > 0:
            node = queue.popleft()
            distances[node] = level
            for neighbor in graph[node]:
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append(neighbor)
            nodes_in_level -= 1
        level += 1
    return distances


def translate_distance_map(
    tables: list[str], distances: dict[int, int]
) -> dict[str, int]:
    """Translates a map of distances from (index -> distance) to (table name -> distance)"""

    return {
        tables[index]: distance
        for index, distance in distances.items()
        if distance != 0
    }


def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
    partitions: list[str],
) -> None:
    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    loader = DeltaLoader()
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}/{table_name}",
        source_df=dataframe,
        partition_by=partitions,
    )


if __name__ == "__main__":
    main()
