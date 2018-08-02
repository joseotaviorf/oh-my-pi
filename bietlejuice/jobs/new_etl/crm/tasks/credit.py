from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR
from bietlejuice.jobs.new_etl.crm.tasks.tasks import CRMTasks


class CRMTasksCredit(CRMTasks):
    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, _class, execution_date):
        super(CRMTasksCredit, self).__init__(s3_bucket, mongo_client_uri, _class, execution_date)

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data(
            _type='EnviarCardiff'
        )

    @logger
    def move_to_clean(self):
        query = BaseETL.get_query_from_file_name(
            '{}/crm/tasks/{}/raw_transform.sql'.format(DATALAKE_QUERIES_DIR, self._class))

        r_cols = OrderedDict([
            ('origem_id', str),
            ('origem_data', str),
            ('assignee_id', str),
            ('resolvida', str),
            ('score_factor', str),
            ('actions', str),
            ('data_inicio', str),
            ('v', str),
            ('origem', str),
            ('destinatario_id', str),
            ('id', str),
            ('type', str),
            ('realizada_em', str),
            ('metadata', str)
        ])

        c_cols = OrderedDict([
            ('id_origin', long),
            ('dt_origin', str),
            ('id_assignee', long),
            ('solved', bool),
            ('score_factor', float),
            ('actions', str),
            ('dt_start', str),
            ('version', int),
            ('origin', str),
            ('id_receiver', long),
            ('id', str),
            ('type', str),
            ('dt_completed', str),
            ('metadata', str)
        ])

        self._move_to_clean(
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols
        )
