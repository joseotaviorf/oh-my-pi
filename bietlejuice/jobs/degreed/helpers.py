import json
import uuid


def _clean_keys_recursive(obj):
    """
    Recursively walks a data structure and replaces hyphens with underscores in dictionary keys.
    """
    if isinstance(obj, dict):
        return {k.replace("-", "_"): _clean_keys_recursive(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [_clean_keys_recursive(elem) for elem in obj]
    else:
        return obj


def json_to_dataframe(spark, dbutils, api_data_list: list):
    """
    Converts a list of dictionary-like objects into a Spark DataFrame
    using a temporary JSON file to robustly infer the schema.

    This method is a workaround for the PySpark error:
    [CANNOT_INFER_TYPE_FOR_FIELD] when a field contains inconsistent types
    like an empty list in some records and a list of objects in others.

    Args:
        spark (SparkSession): The active Spark session.
        dbutils (DBUtils): The Databricks utils instance.
        api_data_list (list): A list of dictionaries (JSON-serializable).

    Returns:
        DataFrame: A Spark DataFrame created from the list.
    """
    if not api_data_list:
        return spark.createDataFrame([], schema=None)

    cleaned_api_data_list = [_clean_keys_recursive(record) for record in api_data_list]

    temp_file_name = f"temp_data_{uuid.uuid4()}.json"
    temp_json_path = f"/tmp/{temp_file_name}"

    json_lines_data = "\n".join(
        [json.dumps(record) for record in cleaned_api_data_list]
    )

    dbutils.fs.put(temp_json_path, json_lines_data, overwrite=True)

    return spark.read.json(temp_json_path)
