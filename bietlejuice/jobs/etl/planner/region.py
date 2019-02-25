from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.planner.planner import Planner
from bietlejuice.jobs.etl.planner.planner_table_enum import PlannerTableEnum

logger = QuintoAndarLogger('PlannerRegion')


class PlannerRegion(Planner):
    ENDPOINT = 'http://planner.quintoandar.com.br/schedules/bi/region/{id_region}'

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(PlannerRegion, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def get_class_ids(self):
        return self._get_class_ids(enum_type=PlannerTableEnum.REGION)

    @logger
    def extract_data(self, id_class):
        return self._extract_data(
            enum_type=PlannerTableEnum.REGION,
            endpoint=PlannerRegion.ENDPOINT,
            id_region=id_class
        )

    @logger(exclude='_json')
    def save_into_s3_raw(self, _json, id_class):
        # since the response json returns schedules for the next 10 days,
        # we have to filter the ones with the current execution date
        daily_json = {
            'visit': _json['visit'],
            'schedules': _json['schedules'][self.execution_date] if self.execution_date in _json['schedules'] else {}
        }

        self._save_into_s3_raw(
            _json=daily_json,
            enum_type=PlannerTableEnum.REGION,
            id_class=id_class
        )

    @logger
    def upsert_single_raw_partition(self, id_class):
        self._upsert_single_raw_partition(
            enum_type=PlannerTableEnum.REGION,
            id_class=id_class
        )

    @logger
    def move_to_clean(self, id_class):
        r_cols = OrderedDict([
            ('visit', str),
            ('available', str),
            ('status', str),
            ('available_agents', str),
            ('id', str),
            ('time', str)
        ])

        c_cols = OrderedDict([
            ('visit', str),
            ('slot_available', bool),
            ('slot_status', str),
            ('slot_available_agents', str),
            ('slot_id', long),
            ('slot_time', str)
        ])

        self._move_to_clean(
            enum_type=PlannerTableEnum.REGION,
            id_class=id_class,
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def upsert_single_clean_partition(self, id_class):
        self._upsert_single_clean_partition(
            enum_type=PlannerTableEnum.REGION,
            id_class=id_class
        )
