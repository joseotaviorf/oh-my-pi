import logging

from quintoandar_logger import QuintoAndarLogger

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("{{ task_name }}")

if __name__ == "__main__":
    logger.info("m=__main__, msg=File created by cookiecutter. Please implement me!")
