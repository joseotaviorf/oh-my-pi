import argparse
import re

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.services import FileService, ConfigurationService
from bietlejuice.jobs.composer.services.git_service import GitService

logger = QuintoAndarLogger("validate_datamarts_metadata_files_exist")

DATAMARTS_DAG_REGEX = re.compile(
    r"/dags/dw_datamarts/(?P<context>\w+)/(?P<dagname>\w+)\.py"
)
DATAMARTS_YAML_REGEX = re.compile(
    r"/dags/dw_datamarts/(?P<context>\w+)/(?P<dagname>\w+)_(:?forno|prod)_conf\.(:?yml|yaml)"
)


def get_all_datamarts_files():
    return {
        file: "M"
        for file in FileService.list_dag_files()
        if re.search(DATAMARTS_DAG_REGEX, file)
    }


def get_files_from_diff(branch):
    if branch == "master":
        from_branch = "HEAD~1"
    else:
        from_branch = "origin/master"

    git_service = GitService()
    return git_service.get_modified_files_from_diff(from_branch, "HEAD")


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
        files = get_all_datamarts_files()
    else:
        files = get_files_from_diff(branch)

    if not files:
        print(f"No new/modified files found")
        exit(0)

    failed = []

    for file, status in files.items():
        if status == "D":
            logger.debug(f"file={file} msg=Skipping deleted file")
            continue

        match_dag = re.search(DATAMARTS_DAG_REGEX, file)
        match_yaml = re.search(DATAMARTS_YAML_REGEX, file)

        if match_dag:
            match_dict = match_dag.groupdict()
        elif match_yaml:
            match_dict = match_yaml.groupdict()
        else:
            # skipping non-matched file
            continue

        context = match_dict.get("context")
        dag_name = match_dict.get("dagname")
        if context and dag_name:
            intermediate_path = f"dw_datamarts/{context}"
            configs = ConfigurationService(
                dag_name, intermediate_path=intermediate_path, env="prod"
            )
            for pipeline, pipe_configs in configs.get_config("pipeline").items():
                table_name = pipe_configs["dw"]["table"]
                if not FileService.metadata_file_exists(
                    intermediate_path, "dw", table_name
                ):
                    failed.append((intermediate_path, table_name))

    if failed:
        print("Datamart tables without metadata files:")
        for intermediate_path, table_name in failed:
            print(f"dag={intermediate_path} table={table_name}")
        print("Please create missing lineage YAML files")
        exit(1)
    else:
        print("All files successfully validated!")
        exit(0)


if __name__ == "__main__":
    main()
