"""
This Spark job is only here too keep the job cluster up for half an hour, for the cluster pool stress test.
"""

from quintoandar_logger import QuintoAndarLogger
from time import sleep

logger = QuintoAndarLogger("wait_half_hour")

for minutes_left in range(30, 0, -1):
    logger.info(f"{minutes_left} minutes left")
    sleep(60)

logger.info("Finished")