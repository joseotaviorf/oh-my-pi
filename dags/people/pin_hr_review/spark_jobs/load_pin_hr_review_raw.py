from bietlejuice.jobs.oracle_integration_cloud.main import OICPipeline
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_pin_hr_review_raw"
DATABRICKS_SCOPE = "people"
LOGGER = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    pipeline = OICPipeline()
    pipeline.run()
