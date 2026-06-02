from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.oracle_integration_cloud.main import OICPipeline

# Cluster validation: add_validation_target_args / resolve_datalake_write_target
# (--target-database-name, --target-table-name) via OICPipeline + RawLayerLoader.

JOB_NAME = "load_pin_benefits_raw"
DATABRICKS_SCOPE = "people"
LOGGER = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    pipeline = OICPipeline()
    pipeline.run()
