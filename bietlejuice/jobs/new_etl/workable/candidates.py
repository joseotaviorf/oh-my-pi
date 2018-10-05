from ordereddict import OrderedDict
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.new_etl.workable.workable import Workable

logger = QuintoAndarLogger('WorkableCandidates')


class WorkableCandidates(Workable):
    DIM_TABLE_NAME = 'candidate'

    @logger(exclude='access_token')
    def __init__(self, s3_bucket, url_prefix, access_token):
        super(WorkableCandidates, self).__init__(
            s3_bucket=s3_bucket,
            url_prefix=url_prefix,
            access_token=access_token
        )

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('firstname', str),
            ('lastname', str),
            ('headline', str),
            ('account_subdomain', str),
            ('account_name', str),
            ('job_short_code', str),
            ('job_title', str),
            ('stage', str),
            ('disqualified', str),
            ('disqualification_reason', str),
            ('sourced', str),
            ('profile_url', str),
            ('email', str),
            ('domain', str),
            ('created_at', str),
            ('updated_at', str),
            ('hired_at', str),
            ('address', str),
            ('phone', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('first_name', str),
            ('last_name', str),
            ('headline', str),
            ('account_subdomain', str),
            ('account_name', str),
            ('job_short_code', str),
            ('job_title', str),
            ('stage', str),
            ('disqualified', str),
            ('disqualification_reason', str),
            ('sourced', str),
            ('profile_url', str),
            ('email', str),
            ('domain', str),
            ('created_at', str),
            ('updated_at', str),
            ('hired_at', str),
            ('address', str),
            ('phone', str)
        ])

        self._move_to_clean(
            enum_type=Workable.TypeEnum.CANDIDATES,
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def extract_data(self):
        return self._extract_data(Workable.TypeEnum.CANDIDATES)

    @logger(exclude='json_list')
    def save_into_s3_raw(self, json_list):
        self._save_into_s3_raw(
            json_list=json_list,
            enum_type=Workable.TypeEnum.CANDIDATES
        )

    @logger
    def move_to_staging_dim(self):
        self._move_to_staging_dim(
            enum_type=Workable.TypeEnum.CANDIDATES,
            table_name=WorkableCandidates.DIM_TABLE_NAME
        )

    @logger
    def move_dim_to_dw(self):
        self._move_to_dw(table_name='dim_{}'.format(WorkableCandidates.DIM_TABLE_NAME))

    @logger
    def delete_dim_staging_entries(self):
        self._delete_staging_entries(table_name='dim_{}'.format(WorkableCandidates.DIM_TABLE_NAME))
