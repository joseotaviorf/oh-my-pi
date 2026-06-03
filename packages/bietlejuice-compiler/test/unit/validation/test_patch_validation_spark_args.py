import sys
from pathlib import Path

_COMPILER_ROOT = Path(__file__).resolve().parents[3]
if str(_COMPILER_ROOT) not in sys.path:
    sys.path.insert(0, str(_COMPILER_ROOT))

from scripts.validation.patch_validation_spark_args import (  # noqa: E402
    _append_validation_params,
    _patch_main_function_targets,
    _patch_pipeline_writes,
    _patch_resolve_in_args_helpers,
    patch_file,
)

_PIPELINE_SAMPLE = """
from bietlejuice.pipeline import IncrementalTableLoaderPipeline

    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = resolve_datalake_write_target(
        prod_database=database_name,
        prod_table=table_name,
        prod_location=database_location,
        bucket=bucket,
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    IncrementalTableLoaderPipeline(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        layer=LayerEnum.RAW,
    ).load_and_register(df, format_options)
"""


def test_patch_pipeline_writes_after_resolve_datalake_write_target():
    patched = _patch_pipeline_writes(_PIPELINE_SAMPLE)

    assert "database_name=write_database_name," in patched
    assert "table_name=write_table_name," in patched
    assert "database_location=write_location," in patched
    assert "database_name=database_name," not in patched
    assert "prod_database=database_name" in patched


def test_patch_pipeline_writes_is_idempotent():
    once = _patch_pipeline_writes(_PIPELINE_SAMPLE)
    twice = _patch_pipeline_writes(once)
    assert once == twice


def test_append_validation_params_without_leading_comma_for_empty_signature():
    assert _append_validation_params("") == (
        "target_database_name: str = None,\n    target_table_name: str = None,\n"
    )
    assert _append_validation_params("environment: str") == (
        "environment: str,\n    target_database_name: str = None,\n    target_table_name: str = None,\n"
    )


def test_patch_main_function_targets_skips_parse_arguments_delegate():
    sample = """
def parse_arguments():
    parser = ArgumentParser()
    add_validation_target_args(parser)
    args = parser.parse_args()
    return environment, args.target_database_name, args.target_table_name

def main():
    environment, target_database_name, target_table_name = parse_arguments()
"""
    assert _patch_main_function_targets(sample) == sample


def test_patch_main_function_targets_appends_params_to_existing_signature():
    sample = "def main(environment: str, bucket: str):\n    pass\n"
    patched = _patch_main_function_targets(sample)
    assert "def main(environment: str, bucket: str," in patched
    assert "target_database_name: str = None" in patched
    assert "def main(," not in patched


def test_patch_resolve_in_args_helpers():
    sample = """
def _load_dataframe_into_datalake(args, force_recreate=True):
    write_database_name, write_table_name, write_location = resolve_datalake_write_target(
        prod_database=database_name,
        prod_table=table_name,
        prod_location=database_location,
        bucket=bucket,
        target_database=target_database_name,
        target_table=target_table_name,
    )
"""
    patched = _patch_resolve_in_args_helpers(sample)
    assert "target_database=args.target_database_name" in patched
    assert "target_table=args.target_table_name" in patched


def test_patch_file_repairs_partially_patched_pipeline_job(tmp_path: Path):
    job = tmp_path / "load_sample_raw.py"
    job.write_text(
        """
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.pipeline import IncrementalTableLoaderPipeline

if __name__ == "__main__":
    add_validation_target_args(parser)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    write_database_name, write_table_name, write_location = resolve_datalake_write_target(
        prod_database=database_name,
        prod_table=table_name,
        prod_location=database_location,
        bucket=bucket,
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    IncrementalTableLoaderPipeline(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        layer=LayerEnum.RAW,
    ).load_and_register(df, format_options)
""".strip()
        + "\n",
        encoding="utf-8",
    )

    assert patch_file(job) is True
    text = job.read_text(encoding="utf-8")
    assert "database_name=write_database_name," in text
    assert "database_name=database_name," not in text


def test_patch_file_skips_fully_patched_job(tmp_path: Path):
    job = tmp_path / "load_sample_raw.py"
    job.write_text(
        """
from bietlejuice.base.validation.spark_args import resolve_datalake_write_target

if __name__ == "__main__":
    write_database_name, write_table_name, write_location = resolve_datalake_write_target(
        prod_database=database_name,
        prod_table=table_name,
        prod_location=database_location,
        bucket=bucket,
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    s3_loader.load_df(df=df, s3_path=f"{write_location}{write_table_name}")
""".strip()
        + "\n",
        encoding="utf-8",
    )

    assert patch_file(job) is False
