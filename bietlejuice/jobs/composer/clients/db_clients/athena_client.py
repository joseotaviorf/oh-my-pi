from time import sleep

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients.db_client import DBClient

logger = QuintoAndarLogger("AthenaClient")


class AthenaClient(DBClient):
    """
    Run commands and return query results in AWS Athena.

    :param database: Database to which the queries or commands below.
    :type database: str
    :param region_name: AWS Athena region name.
    :type region_name: str
    :param sleep_time: Time to wait between two consecutive call to check query or
    command status on AWS Athena.
    :type sleep_time: int
    """

    INTERMEDIATE_STATES = ("QUEUED", "RUNNING")
    FAILURE_STATES = ("FAILED", "CANCELLED")
    SUCCESS_STATES = ("SUCCEEDED",)

    def __init__(
        self, output_location, database="default", region_name="us-east-1", sleep_time=5
    ):
        self.output_location = output_location
        self.database = database
        self.query_context = {"Database": self.database}
        self.result_configuration = {"OutputLocation": self.output_location}
        self.region_name = region_name
        self.sleep_time = sleep_time
        self._conn = None

    @property
    def conn(self):
        if not self._conn:
            session = boto3.session.Session()
            self._conn = session.client("athena", self.region_name)
        return self._conn

    @logger
    def get_records(self, query, parameters=None):
        response = self.conn.start_query_execution(
            QueryString=query,
            QueryExecutionContext=self.query_context,
            ResultConfiguration=self.result_configuration,
        )

        query_execution_id = response["QueryExecutionId"]

        query_state = self._poll_query_status(query_execution_id)

        if query_state in self.FAILURE_STATES:
            reason = self._get_query_status_change_reason(query_execution_id)
            raise RuntimeError(
                "m=get_records, query_execution_id={}, msg=Query "
                "failed, e={}".format(query_execution_id, reason)
            )

        result = self._get_query_results(query_execution_id)

        return result

    @logger
    def run(self, command, autocommit=False, parameters=None, return_query_id=False):
        response = self.conn.start_query_execution(
            QueryString=command,
            QueryExecutionContext=self.query_context,
            ResultConfiguration=self.result_configuration,
        )

        query_execution_id = response["QueryExecutionId"]

        query_state = self._poll_query_status(query_execution_id)

        if query_state in self.FAILURE_STATES:
            reason = self._get_query_status_change_reason(query_execution_id)
            raise RuntimeError(
                "m=run, query_execution_id={}, msg=Query "
                "failed, e={}".format(query_execution_id, reason)
            )

        if return_query_id:
            return query_execution_id

    def _poll_query_status(self, query_execution_id, max_tries=None):
        """
        Poll the status of submitted athena query until query state reaches final
        state. Returns one of the final states

        :param query_execution_id: Id of submitted athena query
        :type query_execution_id: str
        :param max_tries: Number of times to poll for query state before function exits
        :type max_tries: int
        :return: str
        """
        # todo: set a default value for max_tries param to avoid an unlikely infinite
        #  loop in case a query never reaches a final state.
        try_number = 1
        while True:
            query_state = self._get_query_status(query_execution_id)
            if query_state is None:
                logger.info(
                    "m=_poll_query_status, msg=Trial {try_number}: Invalid query state."
                    "Retrying again".format(try_number=try_number)
                )
            elif query_state in self.INTERMEDIATE_STATES:
                logger.info(
                    "m=_poll_query_status, msg=Trial {try_number}: Query is still in an"
                    "intermediate state - {state}".format(
                        try_number=try_number, state=query_state
                    )
                )
            else:
                logger.info(
                    "m=_poll_query_status, msg=Trial {try_number}: Query execution"
                    "completed. Final state is {state}".format(
                        try_number=try_number, state=query_state
                    )
                )
                return query_state

            if max_tries and try_number >= max_tries:
                return query_state

            try_number += 1
            sleep(self.sleep_time)

    def _get_query_status(self, query_execution_id):
        """
        Fetch the status of submitted athena query. Returns None or one of valid
        query states.

        :param query_execution_id: Id of submitted athena query
        :type query_execution_id: str
        :return: str
        """
        response = self.conn.get_query_execution(QueryExecutionId=query_execution_id)
        state = None
        try:
            state = response["QueryExecution"]["Status"]["State"]
        except Exception as ex:
            raise RuntimeError(
                "m=_get_query_status, msg=Exception while getting query state, "
                "e={}".format(ex)
            )

        return state

    def _get_query_results(self, query_execution_id):
        """
        Fetch submitted athena query results. Returns None if query is in intermediate
        state or failed/cancelled state else dict of query output

        :param query_execution_id: Id of submitted athena query
        :type query_execution_id: str
        :return: dict
        """
        query_state = self._get_query_status(query_execution_id)
        if query_state is None:
            raise RuntimeError("m=_get_query_results, msg=Invalid Query state")
        if (
            query_state in self.INTERMEDIATE_STATES
            or query_state in self.FAILURE_STATES
        ):
            logger.warning(
                "m=_get_query_results, msg=Query is in {state} state. "
                "Cannot fetch results".format(state=query_state)
            )
            return None
        return self.conn.get_query_results(QueryExecutionId=query_execution_id)

    def _get_query_status_change_reason(self, query_execution_id):
        """
        Fetch the status change reason of submitted athena query.

        :param query_execution_id: Id of submitted athena query
        :type query_execution_id: str
        :return: str
        """
        response = self.conn.get_query_execution(QueryExecutionId=query_execution_id)
        reason = None
        try:
            reason = response["QueryExecution"]["Status"]["StateChangeReason"]
        except Exception as ex:
            raise RuntimeError(
                "m=_get_query_status_change_reason, msg=Exception while getting state"
                "change reason of the query, e={}".format(ex)
            )
        finally:
            return reason
