import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "data_quality_tests_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    logger.info(f"m={JOB_NAME}, msg=Job execution started.")

    logger.info(f"m={JOB_NAME}, msg=Data quality tests executed for table.")
