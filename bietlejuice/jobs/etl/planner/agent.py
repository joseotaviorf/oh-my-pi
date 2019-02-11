from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.planner.planner import Planner

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
    def get_class_ids(self):
        raise NotImplementedError('m=get_class_ids, msg=method not implemented')

    def extract_data(self, id_class):
        raise NotImplementedError('m=extract_data, msg=method not implemented')

    def save_into_s3_raw(self, _json, id_class):
        raise NotImplementedError('m=save_into_s3_raw, msg=method not implemented')

    def upsert_single_raw_partition(self, id_class):
        raise NotImplementedError('m=upsert_single_raw_partition, msg=method not implemented')

    def upsert_single_clean_partition(self, id_class):
        raise NotImplementedError('m=upsert_single_clean_partition, msg=method not implemented')

    def move_to_clean(self, id_class):
        raise NotImplementedError('m=move_to_clean, msg=method not implemented')
