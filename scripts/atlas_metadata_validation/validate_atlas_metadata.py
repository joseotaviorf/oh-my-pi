import argparse
import re
import subprocess
from typing import List, Iterable, Set

import yamale

GIT_DIFF_REGEX = re.compile(
    r"bietlejuice/jobs/composer/db/datalake/metadata/.*(?:\.yml|\.yaml)"
)
FILENAME_REGEX = re.compile(r".*/([a-z_-]+)(?:\.yml|\.yaml)")

YAML_SCHEMAS = {
    "tags": yamale.make_schema(
        "scripts/atlas_metadata_validation/atlas_metadata_schemas/tags_schema.yml"
    ),
    "lineage": yamale.make_schema(
        "scripts/atlas_metadata_validation/atlas_metadata_schemas/lineage_schema.yml"
    ),
}


def get_modified_documentation_from_diff(branch: str) -> Set[str]:
    """
    Compares current branch with the master branch and gets all the new / modified
    documentation files and their status

    Args:
    branch:
        The current branch, which will be compared to master. If branch == master, then it will compare to the last
        commit
    Returns:
        A set of strings, each containing the path to a modified file and the file status according to git diff-tree
    """
    diff_branches = "origin/master..HEAD"
    if branch == "master":
        diff_branches = "HEAD~1..HEAD"

    bash_command = f"git diff-tree --no-commit-id --name-status -r {diff_branches}"
    process = subprocess.Popen(bash_command.split(), stdout=subprocess.PIPE)
    output, _ = process.communicate()
    decoded_output = output.decode("utf-8").splitlines()

    modified_documentation = set(
        [entry for entry in decoded_output if re.search(GIT_DIFF_REGEX, entry)]
    )

    return modified_documentation


def split_status_and_file_path(
    modified_documentations: Set[str],
) -> Iterable[List[str]]:
    for status_and_file in modified_documentations:
        yield status_and_file.split("\t")


def get_first_key(input_dict: dict) -> str:
    """
    Returns the first key of a dict
    """
    return next(iter(input_dict))


def get_yaml_type(yaml_data: dict) -> str:
    """
    Given a yaml with Atlas metadata information about a table,
    returns whether this file has the table lineage or tags

    Args:
         yaml_data: dict containing the yaml data
    Returns:
        a string with either "tags" or "lineage"
    """
    yaml_content = yaml_data[0][0]
    first_column_name = get_first_key(yaml_content["columns"])
    return get_first_key(yaml_content["columns"][first_column_name])


def validate_yaml_schema(yaml_data: dict):
    """
    Checks if yaml_data complies with lineage or tags schema
    Args:
        yaml_data: tuple containing yaml data. Created using yamale.make_data()
    Raises:
        YamaleError: if the file does not comply with tags or lineage schemas
        ValueError: if the file has a field under columns that isn't lineage or tags
    """

    yaml_type = get_yaml_type(yaml_data)

    if yaml_type not in YAML_SCHEMAS:
        file_path = yaml_data[0][1]
        raise ValueError(
            f"file_path={file_path} yaml_type={yaml_type} "
            f"msg=Columns defined in the file should only have 'lineage' or 'tags', found '{yaml_type}'"
        )

    yamale.validate(YAML_SCHEMAS[yaml_type], yaml_data)


def validate_file_name_matches_table_name(file_path: str, yaml_content: dict):
    """
    Checks if the table_name field in the yaml matches the file name
    Args:
        file_path: path to yaml file
        yaml_content: dict with yaml content
    Raises:
        ValueError: if the names do not match
    """
    file_name = re.search(FILENAME_REGEX, file_path).group(1)
    table_name = yaml_content["table_name"]
    if file_name != table_name:
        raise ValueError(
            f"file_name={file_name} table_name={table_name} file_path={file_path} "
            f"msg=The name defined under 'table_name' in metadata file is not the same as the file name. "
            f"Make sure the file name is the same as the table_name key "
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(dest="branch")
    args = parser.parse_args()

    branch = args.branch
    modified_documentations = get_modified_documentation_from_diff(branch)

    if modified_documentations:
        for git_status, file_path in split_status_and_file_path(
            modified_documentations
        ):
            if git_status == "D":
                # no validation is required when a file is deleted
                print(
                    f"file_path={file_path} git_status={git_status} msg=Skipping deleted file"
                )
                continue
            print(
                f"file_path={file_path} git_status={git_status} msg=Validating Atlas metadata file"
            )

            yaml_data = yamale.make_data(file_path)  # reads YAML
            yaml_content = yaml_data[0][0]
            file_path = yaml_data[0][1]

            validate_yaml_schema(yaml_data)
            validate_file_name_matches_table_name(file_path, yaml_content)
        print("msg=Successfully validated all files!")
    else:
        print("msg=No changes found on Atlas metadata files")


if __name__ == "__main__":
    main()
