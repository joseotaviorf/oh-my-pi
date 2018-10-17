from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.new_etl.planner.planner import Planner

logger = QuintoAndarLogger('PlannerAgent')


class PlannerAgent(Planner):
    ENDPOINT = 'http://planner.quintoandar.com.br/schedules/bi/agent/{id_agent}/availability/{date}'

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(PlannerAgent, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    # TODO: implement agent planner ELT
