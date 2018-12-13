from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR

logger = QuintoAndarLogger("Zendesk")

athena_client = AthenaClient('5a-datalake')

query = BaseETL.get_query_from_file_name('{}/zendesk/tickets.sql'.format(DATALAKE_QUERIES_DIR))

r_cols = OrderedDict([
    ('subject', str),
    ('created_at', str),
    ('description', str),
    ('external_id', str),
    ('type', str),
    ('channel', str),
    ('source', str),
    ('updated_at', str),
    ('problem_id', str),
    ('due_at', str),
    ('id', str),
    ('assignee_id', str),
    ('generated_timestamp', str),
    ('raw_subject', str),
    ('forum_topic_id', str),
    ('custom_fields', str),
    ('allow_channelback', str),
    ('satisfaction_rating', str),
    ('submitter_id', str),
    ('priority', str),
    ('collaborator_ids', str),
    ('tags', str),
    ('brand_id', str),
    ('metric_set', str),
    ('group_id', str),
    ('organization_id', str),
    ('recipient', str),
    ('is_public', str),
    ('has_incidents', str),
    ('status', str),
    ('requester_id', str)
])

r_cols = OrderedDict([
    ('subject', str),
    ('created_at', str),
    ('description', str),
    ('external_id', int),
    ('type', str),
    ('channel', str),
    ('source', str),
    ('updated_at', str),
    ('problem_id', int),
    ('due_at', str),
    ('id', int),
    ('assignee_id', int),
    ('generated_timestamp', str),
    ('raw_subject', str),
    ('forum_topic_id', str),
    ('custom_fields', str),
    ('allow_channelback', str),
    ('satisfaction_rating', str),
    ('submitter_id', int),
    ('priority', str),
    ('collaborator_ids', str),
    ('tags', str),
    ('brand_id', int),
    ('metric_set', str),
    ('group_id', int),
    ('organization_id', int),
    ('recipient', str),
    ('is_public', bool),
    ('has_incidents', bool),
    ('status', str),
    ('requester_id', int)
])

athena_client.create_parquet_from_query(
    key="clean/zendesk/tickets/dt_created=2018-12-13/2018-12-13.parquet",
    query=query,
    raw_columns=r_cols,
    clean_columns=r_cols
)
