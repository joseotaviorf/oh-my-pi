import json
import os
from pathlib import Path

import pandas as pd
import yaml


class Dumper(yaml.Dumper):
    def increase_indent(self, flow=False, *args, **kwargs):
        return super().increase_indent(flow=flow, indentless=False)


def get_databricks_profile(option):
    if option == 1:
        return "DEFAULT"
    elif option == 2:
        return "PROD"
    elif option == 3:
        return "FORNO"


def get_doc_data_frame(table, option):
    user_root_path = os.path.expanduser("~")
    source_doc_path = f"dbfs:/{table}_doc"
    destination_doc_path = os.path.join(user_root_path, f"{table}_doc")
    os.system(
        f"databricks fs cp -r {source_doc_path} {destination_doc_path} --profile={get_databricks_profile(option)}"
    )
    df = pd.read_parquet(f"{destination_doc_path}")
    os.system(
        f"databricks fs rm -r {source_doc_path} --profile={get_databricks_profile(option)}"
    )
    os.system(f"rm -rf {destination_doc_path}")

    return df


file_name = str(input("Json file name: "))
print("""
Databricks Profiles
    1 - Default
    2 - Prod
    3 - Forno
""")
select_profile = int(input("Select profile: "))

path = Path(__file__).absolute()
BIETLEJUICE_ROOT = path.parent.parent.parent.absolute()
path_infos = os.path.join(BIETLEJUICE_ROOT, f"scripts/documentations/{file_name}.json")

json_file = open(path_infos)
json_content = json.load(json_file)
json_file.close()

for dag_name, dag_infos in json_content.items():
    dag = dag_name
    line = dag_infos["line"]
    layer = dag_infos["layer"]
    table = dag_infos["table"]

    yml_path = os.path.join(
        BIETLEJUICE_ROOT, f"dags/{line}/{dag_name}/metadata/{layer}/{table}.yml"
    )
    yml_file_to_read = open(yml_path, encoding="utf-8")
    yml_content = yaml.load(yml_file_to_read)
    yml_file_to_read.close()

    doc_data_frame = get_doc_data_frame(table, select_profile)

    for interator_sheet in range(doc_data_frame.shape[0]):
        yml_content["columns"][doc_data_frame["column"][interator_sheet]][
            "description"
        ] = doc_data_frame["description"][interator_sheet].replace("\n", " ")

    with open(yml_path, "w+") as yml_content_to_write:
        yaml.dump(
            yml_content,
            yml_content_to_write,
            Dumper=Dumper,
            sort_keys=False,
            allow_unicode=True,
        )
