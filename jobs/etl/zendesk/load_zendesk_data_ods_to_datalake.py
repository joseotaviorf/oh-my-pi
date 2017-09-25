import logging
import os
import sys
import petl
from datetime import datetime
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from collections import OrderedDict
from qa_python_utils.aws.athena import AthenaClient

args = sys.argv

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

execution_time = datetime.now()

bucket = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()

athena_client = AthenaClient(bucket)


def load_zendesk_table_to_datalake(table_name, raw_columns):
    _logger.info('m=load_zendesk_table_to_dw, msg=saving {} to dw'.format(table_name))
    key = 'clean/zendesk/{0}/{0}.parq'.format(table_name)
    df = BaseETL.from_db_table(
        db_enum=EnumDb.BI_ODS,
        encoding='UTF8',
        table_name='zendesk.{}'.format(table_name)
    )
    df = petl.todataframe(df)
    athena_client.create_parquet_from_df(
        key=key,
        df=df,
        raw_columns=OrderedDict(raw_columns)
    )
    _logger.info('m=load_zendesk_table_to_dw, msg=saved {} to dw'.format(table_name))

if __name__ == '__main__':
    if args[1] == 'tickets':
        columns = [
            ('id', str),
            ('url', str),
            ('external_id', str),
            ('type', str),
            ('subject', str),
            ('raw_subject', str),
            ('description', str),
            ('priority', str),
            ('status', str),
            ('recipient', str),
            ('requester_id', str),
            ('submitter_id', str),
            ('assignee_id', str),
            ('organization_id', str),
            ('group_id', str),
            ('forum_topic_id', str),
            ('problem_id', str),
            ('has_incidents', bool),
            ('due_at', str),
            ('via_id', long),
            ('satisfaction_rating_score', str),
            ('satisfaction_rating_comment', str),
            ('followup_ids', str),
            ('sharing_agreement_ids', str),
            ('ticket_form_id', str),
            ('brand_id', str),
            ('allow_channelback', bool),
            ('is_public', bool),
            ('created_at', str),
            ('updated_at', str)
        ]
        load_zendesk_table_to_datalake('ticket', columns)
    elif args[1] == 'ticket_metrics':
        columns = [
            ('id', str),
            ('ticket_id', str),
            ('url', str),
            ('group_stations', long),
            ('assignee_stations', long),
            ('reopens', long),
            ('replies', long),
            ('assignee_updated_at', str),
            ('requester_updated_at', str),
            ('status_updated_at', str),
            ('initially_assigned_at', str),
            ('assigned_at', str),
            ('solved_at', str),
            ('latest_comment_added_at', str),
            ('first_resolution_time_in_minutes_calendar', long),
            ('first_resolution_time_in_minutes_business', long),
            ('reply_time_in_minutes_calendar', long),
            ('reply_time_in_minutes_business', long),
            ('full_resolution_time_in_minutes_calendar', long),
            ('full_resolution_time_in_minutes_business', long),
            ('agent_wait_time_in_minutes_calendar', long),
            ('agent_wait_time_in_minutes_business', long),
            ('requester_wait_time_in_minutes_calendar', long),
            ('requester_wait_time_in_minutes_business', long),
            ('created_at', str),
            ('updated_at', str),
            ('on_hold_time_in_minutes_calendar', long),
            ('on_hold_time_in_minutes_business', long)
        ]
        load_zendesk_table_to_datalake('ticket_metrics', columns)
    elif args[1] == 'user':
        columns = [
            ('id', str),
            ('email', str),
            ('name', str),
            ('active', bool),
            ('alias', str),
            ('chat_only', bool),
            ('created_at', str),
            ('custom_role_id', long),
            ('details', str),
            ('external_id', long),
            ('last_login_at', str),
            ('locale', str),
            ('locale_id', long),
            ('moderator', bool),
            ('notes', str),
            ('only_private_comments', bool),
            ('organization_id', str),
            ('default_group_id', str),
            ('phone', str),
            ('photo_id', long),
            ('restricted_agent', bool),
            ('role', str),
            ('shared', bool),
            ('shared_agent', bool),
            ('signature', str),
            ('suspended', bool),
            ('ticket_restriction', str),
            ('time_zone', str),
            ('two_factor_auth_enabled', bool),
            ('updated_at', str),
            ('url', str),
            ('verified', bool)
        ]
        load_zendesk_table_to_datalake('users', columns)
    elif args[1] == 'group_membership':
        columns = [
            ('id', str),
            ('url', str),
            ('user_id', str),
            ('group_id', str),
            ('default', bool),
            ('created_at', str),
            ('updated_at', str)
        ]
        load_zendesk_table_to_datalake('group_memberships', columns)
    elif args[1] == 'group':
        columns = [
            ('id', str),
            ('url', str),
            ('name', str),
            ('deleted', bool),
            ('created_at', str),
            ('updated_at', str)
        ]
        load_zendesk_table_to_datalake('groups', columns)
    elif args[1] == 'ticket_fields_type':
        columns = [
            ('id', str),
            ('ticket_id', str),
            ('value', str)
        ]
        load_zendesk_table_to_datalake('ticket_fields', columns)
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))