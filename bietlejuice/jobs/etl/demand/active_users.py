from collections import OrderedDict
from copy import deepcopy

from bietlejuice.jobs.etl.demand.demand import DemandETL
from bietlejuice.jobs.etl.demand.demand_enum import DemandEnum
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('ActiveUsers_ETL')


class ActiveUsersETL(DemandETL):
    R_COLS = OrderedDict([
        ('event_date', str),
        ('amplitude_id', str),
        ('app', str),
        ('city', str),
        ('region', str),
        ('mkt_category', str),
        ('mkt_flow', str),
        ('mkt_completion', str),
        ('mkt_channel', str),
        ('mkt_medium', str),
        ('mkt_source', str),
        ('mkt_platform', str),
        ('utm_campaign', str),
        ('utm_content', str),
        ('utm_term', str)
    ])
    C_COLS = deepcopy(R_COLS)
    TABLE_NAME = DemandEnum.ACTIVE_USERS.value

    @logger
    def move_to_datalake(self, df, period):
        table_name = '{}_{}'.format(period, self.TABLE_NAME)
        self._move_to_datalake(df=df, table_name=table_name, raw_columns=self.R_COLS, clean_columns=self.C_COLS)

    @logger
    def extract_data(self, period):
        table_name = '{}_{}'.format(period, self.TABLE_NAME)
        return self._extract_data(table_name=table_name)
