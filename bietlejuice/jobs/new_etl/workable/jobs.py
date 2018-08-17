from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.workable.workable import Workable


class WorkableJobs(Workable):
    DIM_TABLE_NAME = 'job'

    @logger(exclude='access_token')
    def __init__(self, s3_bucket, url_prefix, access_token):
        super(WorkableJobs, self).__init__(
            s3_bucket=s3_bucket,
            url_prefix=url_prefix,
            access_token=access_token
        )

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('code', str),
            ('title', str),
            ('url', str),
            ('created_at', str),
            ('shortlink', str),
            ('full_title', str),
            ('state', str),
            ('application_url', str),
            ('location_city', str),
            ('location_region_code', str),
            ('location_telecommuting', str),
            ('location_country', str),
            ('location_region', str),
            ('location_country_code', str),
            ('location_zip_code', str),
            ('department', str),
            ('shortcode', str),
            ('id', str)
        ])

        c_cols = OrderedDict([
            ('code', str),
            ('title', str),
            ('url', str),
            ('created_at', str),
            ('short_link', str),
            ('full_title', str),
            ('state', str),
            ('application_url', str),
            ('location_city', str),
            ('location_region_code', str),
            ('location_telecommuting', str),
            ('location_country', str),
            ('location_region', str),
            ('location_country_code', str),
            ('location_zip_code', str),
            ('department', str),
            ('short_code', str),
            ('id', str)
        ])

        self._move_to_clean(
            enum_type=Workable.TypeEnum.JOBS,
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def extract_data(self):
        return self._extract_data(Workable.TypeEnum.JOBS)

    @logger(exclude='json_list')
    def save_into_s3_raw(self, json_list):
        self._save_into_s3_raw(
            json_list=json_list,
            enum_type=Workable.TypeEnum.JOBS
        )

    @logger
    def move_to_staging_dim(self):
        self._move_to_staging_dim(
            enum_type=Workable.TypeEnum.JOBS,
            table_name=WorkableJobs.DIM_TABLE_NAME
        )

    @logger
    def move_dim_to_dw(self):
        self._move_to_dw(table_name='dim_{}'.format(WorkableJobs.DIM_TABLE_NAME))

    @logger
    def delete_dim_staging_entries(self):
        self._delete_staging_entries(table_name='dim_{}'.format(WorkableJobs.DIM_TABLE_NAME))
