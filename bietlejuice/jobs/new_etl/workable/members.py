from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.workable.workable import Workable


class WorkableMembers(Workable):
    DIM_TABLE_NAME = 'member'

    @logger(exclude='access_token')
    def __init__(self, s3_bucket, url_prefix, access_token):
        super(WorkableMembers, self).__init__(
            s3_bucket=s3_bucket,
            url_prefix=url_prefix,
            access_token=access_token
        )

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('email', str),
            ('headline', str),
            ('role', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('email', str),
            ('headline', str),
            ('role', str)
        ])

        self._move_to_clean(
            enum_type=Workable.TypeEnum.MEMBERS,
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def extract_data(self):
        return self._extract_data(Workable.TypeEnum.MEMBERS)

    @logger(exclude='json_list')
    def save_into_s3_raw(self, json_list):
        self._save_into_s3_raw(
            json_list=json_list,
            enum_type=Workable.TypeEnum.MEMBERS
        )

    @logger
    def move_to_staging_dim(self):
        self._move_to_staging_dim(
            enum_type=Workable.TypeEnum.MEMBERS,
            table_name=WorkableMembers.DIM_TABLE_NAME
        )

    @logger
    def move_dim_to_dw(self):
        self._move_to_dw(table_name='dim_{}'.format(WorkableMembers.DIM_TABLE_NAME))

    @logger
    def delete_dim_staging_entries(self):
        self._delete_staging_entries(table_name='dim_{}'.format(WorkableMembers.DIM_TABLE_NAME))
