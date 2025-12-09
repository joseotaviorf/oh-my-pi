import logging
import time

try:
    from pyspark.sql.streaming import StreamingQueryListener
    from pyspark.sql.streaming.listener import (
        QueryIdleEvent,
        QueryProgressEvent,
        QueryStartedEvent,
        QueryTerminatedEvent,
    )
except ImportError:
    QueryIdleEvent = None
    QueryProgressEvent = None
    QueryStartedEvent = None
    QueryTerminatedEvent = None

    class StreamingQueryListener:
        pass


logger = logging.getLogger(__name__)


class CDFToKafkaStreamListener(StreamingQueryListener):
    """Listener for CDF to Kafka streaming query events."""

    def __init__(self):
        self.start_time = None

        self.total_rows_written = 0
        self.batches_processed = 0

    def onQueryStarted(self, event: QueryStartedEvent) -> None:
        self.start_time = time.time()
        logger.info("=== onQueryStarted called ===")
        logger.info(
            f"Streaming query started: id={event.id}, name={event.name}, runId={event.runId}"
        )

    def onQueryProgress(self, event: QueryProgressEvent) -> None:
        logger.info("=== onQueryProgress called ===")

        self.total_rows_written += event.progress.numInputRows

        logger.info(f"Batch ID: {event.progress.batchId}")
        logger.info(f"Rows in this batch: {event.progress.numInputRows}")
        logger.info(f"Total rows written: {self.total_rows_written}")
        logger.info(f"Batch duration: {event.progress.batchDuration}ms")
        logger.info(
            f"Processing rate: {event.progress.processedRowsPerSecond} rows/sec"
        )

    def onQueryIdle(self, event: QueryIdleEvent) -> None:
        logger.info("onQueryIdle called")
        logger.info(f"Query is idle (no new data to process) id={event.id}")

    def onQueryTerminated(self, event: QueryTerminatedEvent) -> None:
        logger.info("onQueryTerminated called")
        duration = time.time() - self.start_time if self.start_time else 0

        logger.info(f"Query terminated id={event.id} duration={duration:.2f}s")
        logger.info(f"Total batches processed: {self.batches_processed}")
        logger.info(f"Total rows written to Kafka: {self.total_rows_written}")

        if event.exception:
            logger.error(f"Query failed with exception: {event.exception}")
        else:
            logger.info("Query terminated successfully with no exceptions")
