import argparse
import os
import re
import sys

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.dag_metadata_service import DAGMetadataService
from dags import DAG_PACKAGES_ROOT

BI_ETL_EJUICE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(BI_ETL_EJUICE_ROOT)

from bietlejuice.base.paths import QUERIES_DATALAKE_PATH
from bietlejuice.services.git_service import GitService
from bietlejuice.services.file_service import FileService
from bietlejuice.services.configuration_service import ConfigurationService

logger = QuintoAndarLogger("validate_metadata_files_exist")

# Note: Some marketing tables have an out-of-pattern folder structure,
# where the layer and context are swapped.
# We can skip them by using their contexts as layers, but we should move/remove
# those queries in the future.
SKIP_LAYERS = {
    # TODO: enable lineage from product checks once all product sources are in BigID
    "raw",
    # TODO: remove the following values when those queries are removed/refactored to the new pattern
    "old_sharing_rules",
    "facebook_insights",
    "linkedin",
    "offline",
    "enrich_for_looker"  # DAG regions_polygon
}
SKIP_SOURCES = {}
SKIP_CONTEXTS = {}
SKIP_DAGS = {}
SKIP_TABLES = {
    "poligonoregiao",
    "dw_casa_mineira_portal",
    "fact_ongoing_real_estate_agency",
    "events_affiliates",
    "email_affiliates",
    "inapp_affiliates",
    "push_affiliates",
    "sms_affiliates",
    "webhook_affiliates",
    "affiliates_events",
}

# Some raw/clean DAGs don't use DatalakeTaskGroup and thus won't have a "lineage from product" config.
# Adding them to this set will skip checking for "lineage from product" config in raw tables
DAGS_OUT_OF_PATTERN = {"ebdb", "amplitude"}

# This regex matches the relative path query according to FileService or GitService absolute paths
# e.g.
#   '/Users/root/bi-etl-ejuice/bietlejuice/base/../db/datalake/queries/dag_name/layer/table_name.sql'
#   '/Users/root/bi-etl-ejuice/bietlejuice/db/datalake/queries/dag_name/layer/table_name.sql'
# would both have 'dag_name/layer/table_name.sql' in the first capture group
LEGACY_RELATIVE_QUERY_PATH_REGEX = re.compile(
    rf"bietlejuice(?:/base/\.\.)?/db/datalake/queries/(.*\.sql)"
)
DAG_PACKAGES_RELATIVE_QUERY_PATH_REGEX = re.compile(
    rf"dags\/(.*)\/(.*)\/queries\/(.*)\/(.*)\.sql"
)


def get_all_query_files():
    # legacy files
    all_files = {
        file: "M"
        for file in FileService.list_all_files_recursively(QUERIES_DATALAKE_PATH, "sql")
    }
    # dag_packages
    all_files.update(
        {
            file: "M"
            for file in FileService.list_all_files_recursively(DAG_PACKAGES_ROOT, "sql")
        }
    )
    return all_files


def get_files_from_diff(branch):
    if branch == "master":
        from_branch = "HEAD~1"
    else:
        from_branch = "origin/master"

    git_service = GitService()
    return git_service.get_modified_files_from_diff(from_branch, "HEAD")


def extract_relative_query_path(file_path):
    search_res = re.search(LEGACY_RELATIVE_QUERY_PATH_REGEX, file_path)
    dag_packages_search_res = re.search(
        DAG_PACKAGES_RELATIVE_QUERY_PATH_REGEX, file_path
    )

    # legacy
    if search_res:
        return search_res.group(1)
    elif dag_packages_search_res:
        dag_name = dag_packages_search_res.group(2)
        layer = dag_packages_search_res.group(3)
        table_name = dag_packages_search_res.group(4)

        return f"{dag_name}/{layer}/{table_name}.sql"
    else:
        return None


def dag_has_product_lineage_config(source, context, dag):
    if source == context and context == dag:
        intermediate_path = None
    else:
        intermediate_path = f"{source}/{context}"

    configs = ConfigurationService(dag, intermediate_path=intermediate_path)
    try:
        configs.get_config("lineage_product_database_name")
        return True
    except IndexError:
        return False


def has_lineage_or_tags(source, layer, context, dag, ingestion_type, table):
    if layer in SKIP_LAYERS or source in SKIP_SOURCES or table in SKIP_TABLES:
        logger.debug(f"source={source}, layer={layer}, table={table}, msg=Skipping")
        return True

    if layer == "raw":
        if dag in DAGS_OUT_OF_PATTERN:
            return True
        elif dag_has_product_lineage_config(source, context, dag):
            return True
    if DAGMetadataService.metadata_file_exists(source, layer, table):
        logger.debug(
            f"source={source}, layer={layer}, table={table}, msg=has lineage/tags file"
        )
        return True
    else:
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(dest="branch")
    parser.add_argument(
        "--validate-all-files", dest="validate_all_files", action="store_true"
    )
    args = parser.parse_args()
    validate_all_files = args.validate_all_files
    branch = args.branch

    if validate_all_files:
        files = get_all_query_files()
    else:
        files = get_files_from_diff(branch)

    if not files:
        print(f"No new/modified files found")
        exit(0)

    to_check = []

    for file, status in files.items():
        if status == "D":
            logger.debug(f"file={file} msg=Skipping deleted file")
            continue
        query_path = extract_relative_query_path(file)
        if query_path:
            try:
                # table_info =  (source, layer, context, dag, ingestion_type, table)
                table_info = FileService.get_table_info_from_path(query_path)
            except ValueError:
                logger.debug(f"query_path={query_path} msg=File is not a query file")
                continue
            to_check.append(table_info)
            source, layer, context, dag, ingestion_type, table = table_info
            if layer == "clean":
                # If a clean table was modified, check the same table in raw
                to_check.append((source, "raw", context, dag, ingestion_type, table))

    failed = [entry for entry in to_check if not has_lineage_or_tags(*entry)]

    if failed:
        print("Queries without metadata files or product lineage:")
        for source, layer, context, dag, ingestion_type, table in failed:
            if source != context:
                source_context_dag = f"source={source} context={context} dag={dag}"
            else:
                source_context_dag = f"dag={dag}"
            print(f"{source_context_dag} layer={layer} table={table}")
        print(
            "Please create missing tags/lineage YAML files or add lineage from product config to "
            "raw/clean dags"
        )
        exit(1)
    else:
        print("All files successfully validated!")
        exit(0)


if __name__ == "__main__":
    main()
