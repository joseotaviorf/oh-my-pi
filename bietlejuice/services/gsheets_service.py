import os

from bietlejuice import dags
from bietlejuice.dags import gsheets, gsheets_by_context
from bietlejuice.services import FileService

import pandas as pd


DEPS_YAML_PATH = os.path.dirname(os.path.realpath(dags.__file__)) + "/dependencies.yaml"
GENERIC_GSHEETS_FILES_YAML_PATH = (
    os.path.dirname(os.path.realpath(gsheets.__file__)) + "/gsheets_files.yaml"
)
CONTEXT_GSHEETS_FILES_YAML_PATH = (
    os.path.dirname(os.path.realpath(gsheets_by_context.__file__))
    + "/gsheets_files.yaml"
)


class GsheetsService:
    def __init__(self) -> None:
        pass

    def get_sheets_are_dependencies(self):
        """
        Return the gsheets clean tables that are dependencies to other DAGs on depencencies.yaml
        :return: list[str]
        """
        dependencies_dict = FileService.get_dict_from_yaml_file(DEPS_YAML_PATH)
        all_deps = []

        for dag, deps in dependencies_dict.items():
            all_deps.extend(deps)

        all_deps = list(set(all_deps))

        gsheets_deps = []
        for dep in all_deps:
            if "bietlejuice.gsheets" in dep:
                gsheets_deps.append(dep)

        gsheets_dict = FileService.get_dict_from_yaml_file(
            GENERIC_GSHEETS_FILES_YAML_PATH
        )
        context_gsheets_dict = FileService.get_dict_from_yaml_file(
            CONTEXT_GSHEETS_FILES_YAML_PATH
        )
        df_generic = (
            pd.DataFrame.from_dict(gsheets_dict, orient="index")
            .reset_index(drop=False)
            .rename(columns={"index": "raw_table_name"})
        )
        df_context = (
            pd.DataFrame.from_dict(context_gsheets_dict, orient="index")
            .reset_index(drop=False)
            .rename(columns={"index": "raw_table_name"})
        )
        df = df_generic.append(df_context, ignore_index=True, sort="raw_table_name")
        df = df.drop(
            ["preload_time_in_seconds", "partitioned", "sheet_context", "sheet_id"],
            axis=1,
        )

        dependencies_sheets = []
        for index, row in df.iterrows():
            clean = row["clean_table_name"].replace("_", "-")
            if len([dep for dep in gsheets_deps if clean in dep]) > 0:
                dependencies_sheets.append(row["clean_table_name"])
        return dependencies_sheets
