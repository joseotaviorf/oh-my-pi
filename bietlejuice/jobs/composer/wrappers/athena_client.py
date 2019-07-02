import time

import boto3
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger('AthenaClient')


class AthenaClient:
    """
    This a temporary client for Athena. In the future we are going to use an AWS client existing in its own repository.
    """
    QUERY_OUTPUT_PATH = 's3://5a-datalake/temp/databricks_output/'

    @staticmethod
    def get_athena_client():
        return boto3.client('athena', 'us-east-1')

    @staticmethod
    def start_athena_query(query, database):
        client = AthenaClient.get_athena_client()
        response = client.start_query_execution(
            QueryString=query,
            QueryExecutionContext={
                'Database': database
            },
            ResultConfiguration={
                'OutputLocation': AthenaClient.QUERY_OUTPUT_PATH
            }
        )
        return response

    @staticmethod
    @logger
    def execute_athena_query(query, database):
        execution = AthenaClient.start_athena_query(query, database)
        execution_id = execution['QueryExecutionId']
        state = 'RUNNING'
        client = AthenaClient.get_athena_client()
        while state in ['RUNNING']:
            response = client.get_query_execution(QueryExecutionId=execution_id)
            if 'QueryExecution' in response and \
                    'Status' in response['QueryExecution'] and \
                    'State' in response['QueryExecution']['Status']:
                state = response['QueryExecution']['Status']['State']
                if state == 'FAILED':
                    raise RuntimeError(
                        'm=execute_athena_query, msg=Athena client failed when executing the query., query={}'.format(
                            query))
                elif state == 'SUCCEEDED':
                    return execution_id
            time.sleep(3)
