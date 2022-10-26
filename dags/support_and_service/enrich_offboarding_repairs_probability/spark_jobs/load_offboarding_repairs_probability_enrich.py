import pickle
import re
import unidecode
from datetime import datetime
from argparse import ArgumentParser

import pandas as pd
import numpy as np
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService


JOB_NAME = "load_enrich_offboarding_repairs_probability"
logger = QuintoAndarLogger(JOB_NAME)

# dict used to control how columns are treated on datawrangling, structured as:
# {"column_name": ("data_type_1", is_treatment_col, is_treatment_col_exception, is_freature, is_dummy_feature)}
col_settings = {
    "id_contract": ("int64", 1, 0, 0, 0),
    "house_city": ("str", 0, 0, 0, 1),
    "dt_booked": ("str", 1, 0, 0, 0),
    "dt_started": ("str", 1, 0, 0, 0),
    "is_exit_inspection_opted_out": ("int64", 1, 1, 0, 0),
    "tenant_qty_entry_comment": ("float64", 0, 0, 1, 0),
    "contract_rent": ("float64", 0, 0, 1, 0),
    "contract_is_b2b": ("int64", 0, 0, 1, 0),
    "contract_was_too_early_terminated": ("int64", 1, 0, 0, 0),
    "contract_ndays_started2annulment": ("int64", 0, 0, 1, 0),
    "contract_qty_inspection_itens": ("int64", 0, 0, 1, 0),
    "contract_qty_proponent": ("int64", 0, 0, 1, 0),
    "contract_avg_income": ("float64", 0, 0, 1, 0),
    "contract_avg_boavista": ("float64", 0, 0, 1, 0),
    "contract_avg_serasa": ("float64", 0, 0, 1, 0),
    "contract_qty_repair": ("int64", 0, 1, 1, 0),
    "house_total_area": ("float64", 0, 0, 1, 0),
    "contract_rent_by_area": ("float64", 0, 0, 1, 0),
    "house_qty_visit": ("int64", 0, 0, 1, 0),
    "house_qty_booking_review": ("int64", 0, 1, 1, 0),
    "house_score_painting": ("float64", 0, 1, 0, 0),
    "house_score_cost_benefit": ("float64", 0, 1, 0, 0),
    "house_score_conservation": ("float64", 0, 1, 0, 0),
    "house_has_closet": ("int64", 0, 0, 1, 0),
    "house_has_gas_system": ("int64", 0, 0, 1, 0),
    "house_has_new_plug": ("int64", 0, 0, 1, 0),
    "house_is_pet_friendly": ("int64", 0, 0, 1, 0),
}


def get_col_settings(setting_index):
    """
    Returns a dict, a subset of 'col_settings', with all keys where the tuple
    value at index 'setting_index' is equal to 1.
    """
    return {
        key: value[0]
        for key, value in col_settings.items()
        if value[setting_index] == 1
    }


def normalize_feature_value(value):
    """
    Normalizes a given string, representing a value of a feature, converting it
    to a lowercase, underscore separated, unicode string.
    """
    return (
        unidecode.unidecode(value)
        .lower()
        .replace(" ", "_")
        .replace("'", "_")
        .replace("-", "_")
    )


def get_features_dummies(lst_all, lst_prod, dummy_col_name):
    """
    For a given list of feature values, transform this list into a DataFrame
    of 0s and 1s, where columns are all possible values of this feature.

    lst_all: list of all possible values
    lst_prod: list of current feature values
    dummy_col_name: feature name
    """
    dct_dummies = {}

    for index, value in enumerate(lst_prod):
        if value:
            treated_value = normalize_feature_value(value)
        else:
            treated_value = value
        lst_dummies_values = [
            1 if treated_value in lst_all[i] else 0 for i in range(len(lst_all))
        ]
        dct_dummies[index] = lst_dummies_values
    columns_list = [dummy_col_name + "_" + feature_value for feature_value in lst_all]

    return pd.DataFrame.from_dict(dct_dummies, orient="index", columns=columns_list)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("context")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    context = args.context
    execution_date = args.execution_date

    config_service = ConfigurationService(f"enrich_{source}")
    output_table_name = config_service.get_config("output_table_name")
    partition_cols = config_service.get_config("partition_cols")
    model_filename = config_service.get_config("model_filename")
    threshold = config_service.get_config("threshold")
    input_query = config_service.get_config("input_query")

    logger.info(
        f"""m=__main__, environment={env}, source={source}, context={context},
        datalake_bucket={datalake_bucket}, execution_date={execution_date},
        msg=Starting Spark job..."""
    )

    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(env, context, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    rf = pickle.load(open(model_filename, "rb"))

    df_raw_contract = spark_client.conn.sql(input_query).toPandas()

    dct_treatment_type = get_col_settings(setting_index=1)
    dct_exception_fillna = {key: 0 for key in get_col_settings(2).keys()}

    lst_treatment = list(dct_treatment_type.keys())
    lst_feature = list(get_col_settings(setting_index=3).keys())
    lst_dummy_feature = list(get_col_settings(setting_index=4).keys())

    df_prev_model = (
        df_raw_contract.copy()
        .fillna(dct_exception_fillna)
        .dropna(subset=lst_treatment)
        .astype(dct_treatment_type)
    )
    df_prev_model = df_prev_model.dropna(subset=lst_feature + lst_dummy_feature)

    # add 'house_city' feature
    lst_all_cities = [
        i.replace("house_city_", "")
        for i in list(rf.feature_names_in_)
        if re.compile(r"house_city").match(i)
    ]
    lst_dummies_model = df_prev_model["house_city"].tolist()
    df_dummy_model = get_features_dummies(
        lst_all_cities, lst_dummies_model, "house_city"
    ).reset_index()
    df_prev_model = pd.concat(
        [df_prev_model.reset_index(), df_dummy_model.reset_index()], axis=1
    )

    df_model = df_prev_model.drop(
        columns=list(
            filter(lambda x: x not in ["id_contract", "dt_booked"], lst_treatment)
        )
        + lst_dummy_feature
    ).copy()

    x = df_model.loc[:, rf.feature_names_in_.tolist()]

    y_pred = rf.predict(x)
    y_prob = rf.predict_proba(x)[:, 1]
    y_pred_prob = [1 if y > threshold else 0 for y in y_prob]

    df_prod = pd.concat(
        [
            df_model.loc[:, ["id_contract", "dt_booked"]],
            pd.DataFrame(
                np.round(y_prob * 100, 2),
                columns=["predicted_offboarding_repair_probability"],
            ),
            pd.DataFrame(y_pred_prob, columns=["predicted_offboarding_repair"]),
        ],
        axis=1,
    )

    dt_predicted = datetime.strptime(execution_date, "%Y-%m-%d").date()
    model_filename_value = model_filename.split("/")[-1].split(".")[0]

    df_prod["dt_predicted"] = dt_predicted
    df_prod["threshold"] = threshold
    df_prod["model_filename"] = model_filename_value

    df = spark_client.create_dataframe(df_prod)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=df_prod,
        format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
        s3_path=f"{database_location}{output_table_name}",
        partitions=partition_cols,
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df_prod,
        database_name=database_name,
        table_name=output_table_name,
        format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
        database_location=database_location,
        partitions=partition_cols,
        force_recreate=False,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df_prod,
        database_name=database_name,
        table_name=output_table_name,
        partition_cols=partition_cols,
    )
