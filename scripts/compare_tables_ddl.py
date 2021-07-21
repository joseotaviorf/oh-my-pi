import os
import yaml
import re
import subprocess

ABS_PATH = os.path.dirname(os.path.realpath(__file__))
BASE_DW_DDLS = "bietlejuice/db/dw/ddl/"
BASE_JANUS_DDLS = "bietlejuice/jobs/composer/db/dw/ddl/janus/"
BASE_YAML_FILES = "bietlejuice/jobs/composer/db/dw/tests/janus/"
INCLUDE_PATHS = (
    "bietlejuice/db/dw/dll/|"
    "bietlejuice/jobs/composer/db/dw/ddl/|"
    "bietlejuice/jobs/composer/db/dw/tests/"
)


def remove_command_lines(lines):
    """
    Filter out special chars and commands,
    via regex, from data definition file's content
    :return: `list`
    """
    r = re.compile(
        "(?!(\s*"  # negates ahead; starts with or without spacing
        "((CONSTRAINT)|((DROP|ALTER|CREATE)\s*TABLE)"  # used commands
        "|\(|\)|;|--"  # special chars
        "|DISTKEY|DISTSTYLE|,*PRIMARY KEY"  # optimization keywords
        ").*)"  # followed by any or nothing chars
        "|^$)",  # empty lines
        re.IGNORECASE,
    )
    return list(filter(r.match, lines))


def extract_column_info(lines):
    """
    Remove more specific punctuation and reserved words, via regex
    :return: `list`
    """
    clean_lines = []
    for line in lines:
        # treat data
        clean_line = re.sub(
            "(^\s*,|,\s*$| primary key,*\s*$)",  # remove commas and trim
            "",
            line.strip(),  # trim
        )
        clean_lines.append(clean_line.strip().lower())

    return clean_lines


def convert_to_dict(lines):
    """
    Convert list into dict, splitting items by single space
    :return: `dict`
    """
    dict = {}
    for line in lines:
        splited_line = line.split(" ")
        dict[splited_line[0]] = splited_line[1]  # ignore column specifications in DDL

    return dict


def read_yaml_file(full_file_path):
    """
    Reads the yaml file from `full_file_path`
    :return: a yaml file's content as a `dict`
    """
    if not os.path.isfile(full_file_path):
        raise RuntimeError(
            "file={}, " "msg=Migration file does not exist".format(full_file_path)
        )
    else:
        with open(full_file_path) as stream:
            return yaml.safe_load(stream)


def get_git_diff():
    """
    Uses git commmand in os to identify changes
    :return: `string`
    """
    bashCommand = "git diff-tree --no-commit-id --name-only -r HEAD..HEAD~1 "
    process = subprocess.Popen(bashCommand.split(), stdout=subprocess.PIPE)
    output, error = process.communicate()
    return output


def extract_formatted_dict_from_file(file_path):
    """
    Parse file with formatting procedures
    :return: `dict`
    """
    with open(file_path, "r") as file:
        lines = file.read().split("\n")

    columns_raw = remove_command_lines(lines)
    columns_clean = extract_column_info(columns_raw)
    return convert_to_dict(columns_clean)


def apply_migration_changes(yaml_as_dict, dw_dict):
    """
    Uses yaml migration definitions to apply changes in dw DDL
    :return: `dict`
    """
    for column_definition in yaml_as_dict.get("columns_mapping", []):
        # remove ods_column
        ods_type = dw_dict.pop(column_definition.get("ods_column"), None)
        # add new_column
        dw_dict[
            column_definition.get("new_column", column_definition.get("ods_column"))
        ] = column_definition.get("new_column_type", ods_type)
        # deleting removed columns in migration
        dw_dict.pop(None, None)

    return dw_dict


def compare_ddls():
    """
    Compares all DDLs from janus to its respective table in prod
    :return: None
    """
    for file_name in os.listdir("{}/../{}".format(ABS_PATH, BASE_JANUS_DDLS)):
        print("Opening janus file...")
        table_name = file_name.split(".")[-2]
        janus_file_path = "{}/../{}{}".format(ABS_PATH, BASE_JANUS_DDLS, file_name)

        print("Processing janus ddl file...")
        janus_dict = extract_formatted_dict_from_file(janus_file_path)

        print("Opening migration definition file...")
        yaml_as_dict = read_yaml_file(
            "{}/../{}{}.yaml".format(ABS_PATH, BASE_YAML_FILES, table_name)
        )

        print("Opening origin ddl file...")
        # utilize yaml info to get file
        table_schema = yaml_as_dict.get("dw_schema", "public")
        dw_file_path = "{}/../{}{}/{}".format(
            ABS_PATH, BASE_DW_DDLS, table_schema, file_name
        )

        print("Processing dw ddl file...")
        dw_dict = extract_formatted_dict_from_file(dw_file_path)

        print("Processing keys of dw ddl file...")
        dw_dict_changed = apply_migration_changes(yaml_as_dict, dw_dict)

        # validates match between dicts
        print("Comparing ddl files...")
        error = False
        for col in dw_dict_changed.keys():
            if dw_dict_changed[col] != janus_dict[col]:
                error = True
                print(
                    "table_schema={0}, table_name={1}, "
                    "column={2}, col_type_dw={3}, "
                    "col_type_janus={4}, "
                    "msg=Columns do not match".format(
                        table_schema,
                        table_name,
                        col,
                        dw_dict_changed[col],
                        janus_dict[col],
                    )
                )
        if error:
            raise ValueError(
                "dw_origin_schema={0}, dw_origin_ddl={1}.ddl,"
                "dw_janus_ddl={1}.ddl, migration_file={1}.yaml,"
                "msg=DDls are not matching according to migration file.".format(
                    table_schema, table_name
                )
            )
        print(
            "table={}, msg=Validation success! DDLs matching according to migration "
            "file!".format(table_name)
        )


if __name__ == "__main__":
    print("Checking git differences...")
    git_diffs = get_git_diff()

    if not re.findall(INCLUDE_PATHS, git_diffs):
        print("Skipping DDL comparison check...")
    else:
        print("Running DDL comparison check...")
        # fetch all files in new schema
        compare_ddls()
