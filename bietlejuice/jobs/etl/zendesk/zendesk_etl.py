import petl
from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

logger = QuintoAndarLogger("ZendeskETL")


class ZendeskETL(object):
    WHERE_CLAUSE = '__WHERE_CLAUSE__'

    SCHEMAS = {
        'raw': 'datalake_raw',
        'clean': 'datalake_clean'
    }

    SK_FIELDS = {
        'fact_ticket_metrics': 'sk_ticket',
        'dim_ticket': 'sk_ticket',
        'dim_zendesk_user': 'sk_zendesk_user'
    }

    TABLE_PARTITION_DATE = '__PARTITION_DATE__'

    def __init__(self, bucket, execution_date=None):
        self.s3_bucket = bucket
        self.athena_client = AthenaClient(self.s3_bucket)
        self.execution_datetime = execution_date
        self.execution_date = execution_date.strftime("%Y-%m-%d")

    @logger
    def tickets(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/tickets.sql'
                                                 .format(DATALAKE_QUERIES_DIR))

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

        c_cols = OrderedDict([
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

        self._move_to_clean(
            table_name=table_name,
            key="clean/zendesk/tickets/dt_extraction={dt}/{dt}.parquet".format(dt=self.execution_date),
            query=query.format(dt=self.execution_date),
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def ticket_fields(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/ticket_fields.sql'.format(DATALAKE_QUERIES_DIR))

        r_cols = OrderedDict([
            ('id', str),
            ('title', str),
            ('raw_title', str),
            ('collapsed_for_agents', str),
            ('visible_in_portal', str),
            ('description', str),
            ('active', str),
            ('raw_title_in_portal', str),
            ('created_at', str),
            ('type', str),
            ('raw_description', str),
            ('required', str),
            ('editable_in_portal', str),
            ('required_in_portal', str),
            ('updated_at', str),
            ('system_field_options', str),
            ('removable', str),
            ('regexp_for_validation', str),
            ('position', str),
            ('tag', str),
            ('title_in_portal', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('title', str),
            ('raw_title', str),
            ('is_collapsed_for_agents', str),
            ('is_visible_in_portal', str),
            ('description', str),
            ('is_active', str),
            ('raw_title_in_portal', str),
            ('created_at', str),
            ('type', str),
            ('raw_description', str),
            ('is_required', str),
            ('is_editable_in_portal', str),
            ('is_required_in_portal', str),
            ('updated_at', str),
            ('system_field_options', str),
            ('is_removable', str),
            ('validation_regexp', str),
            ('position', str),
            ('tag', str),
            ('title_in_portal', str)
        ])

        self._move_to_clean(
            table_name=table_name,
            key='clean/zendesk/ticket_fields/dt_extraction={dt}/{dt}.parquet'.format(dt=self.execution_date),
            query=query,
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def ticket_metric_events(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/ticket_metric_events.sql'
                                                 .format(DATALAKE_QUERIES_DIR))

        r_cols = OrderedDict([
            ('id', str),
            ('ticket_id', str),
            ('metric', str),
            ('instance_id', str),
            ('type', str),
            ('time', str),
            ('sla', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('ticket_id', str),
            ('metric', str),
            ('instance_id', str),
            ('type', str),
            ('time', str),
            ('sla', str)
        ])

        self._move_to_clean(
            table_name=table_name,
            key='clean/zendesk/ticket_events/dt_extraction={dt}/{dt}.parquet'.format(dt=self.execution_date),
            query=query.format(dt=self.execution_date),
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def ticket_events(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/ticket_events.sql'
                                                 .format(DATALAKE_QUERIES_DIR))

        r_cols = OrderedDict([
            ('metadata', str),
            ('system', str),
            ('event_type', str),
            ('updater_id', str),
            ('created_at', str),
            ('child_events', str),
            ('id', str),
            ('ticket_id', str),
            ('timestamp', str),
            ('via', str)
        ])

        c_cols = OrderedDict([
            ('metadata', str),
            ('system', str),
            ('event_type', str),
            ('updater_id', str),
            ('created_at', str),
            ('child_events', str),
            ('id', str),
            ('ticket_id', str),
            ('timestamp', str),
            ('via', str)
        ])

        self._move_to_clean(
            table_name=table_name,
            key='clean/zendesk/ticket_metric_events/dt_extraction={dt}/{dt}.parquet'.format(dt=self.execution_date),
            query=query.format(dt=self.execution_date),
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def users(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/users.sql'
                                                 .format(DATALAKE_QUERIES_DIR))

        r_cols = OrderedDict([
            ('id', str),
            ('url', str),
            ('name', str),
            ('email', str),
            ('created_at', str),
            ('updated_at', str),
            ('time_zone', str),
            ('iana_time_zone', str),
            ('phone', str),
            ('shared_phone_number', str),
            ('photo', str),
            ('locale_id', str),
            ('locale', str),
            ('organization_id', str),
            ('role', str),
            ('verified', str),
            ('external_id', str),
            ('tags', str),
            ('alias', str),
            ('active', str),
            ('shared', str),
            ('shared_agent', str),
            ('last_login_at', str),
            ('two_factor_auth_enabled', str),
            ('signature', str),
            ('details', str),
            ('notes', str),
            ('role_type', str),
            ('custom_role_id', str),
            ('moderator', str),
            ('ticket_restriction', str),
            ('only_private_comments', str),
            ('restricted_agent', str),
            ('suspended', str),
            ('chat_only', str),
            ('default_group_id', str),
            ('report_csv', str),
            ('user_fields', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('url', str),
            ('name', str),
            ('email', str),
            ('created_at', str),
            ('updated_at', str),
            ('time_zone', str),
            ('iana_time_zone', str),
            ('phone', str),
            ('shared_phone_number', str),
            ('photo', str),
            ('locale_id', str),
            ('locale', str),
            ('organization_id', str),
            ('role', str),
            ('verified', str),
            ('external_id', str),
            ('tags', str),
            ('alias', str),
            ('active', str),
            ('shared', str),
            ('shared_agent', str),
            ('last_login_at', str),
            ('two_factor_auth_enabled', str),
            ('signature', str),
            ('details', str),
            ('notes', str),
            ('role_type', str),
            ('custom_role_id', str),
            ('moderator', str),
            ('ticket_restriction', str),
            ('only_private_comments', str),
            ('restricted_agent', str),
            ('suspended', str),
            ('chat_only', str),
            ('default_group_id', str),
            ('report_csv', str),
            ('user_fields', str)
        ])

        self._move_to_clean(
            table_name=table_name,
            key='clean/zendesk/users/dt_extraction={dt}/{dt}.parquet'.format(dt=self.execution_date),
            query=query.format(dt=self.execution_date),
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def groups(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/groups.sql'
                                                 .format(DATALAKE_QUERIES_DIR))

        r_cols = OrderedDict([
            ('url', str),
            ('id', str),
            ('name', str),
            ('deleted', str),
            ('created_at', str),
            ('updated_at', str)
        ])

        c_cols = OrderedDict([
            ('url', str),
            ('id', str),
            ('name', str),
            ('deleted', str),
            ('created_at', str),
            ('updated_at', str)
        ])

        self._move_to_clean(
            table_name=table_name,
            key='clean/zendesk/groups/dt_extraction={dt}/{dt}.parquet'.format(dt=self.execution_date),
            query=query.format(dt=self.execution_date),
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def articles(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/articles.sql'
                                                 .format(DATALAKE_QUERIES_DIR))

        r_cols = OrderedDict([
            ('id', str),
            ('url', str),
            ('html_url', str),
            ('author_id', str),
            ('comments_disabled', str),
            ('draft', str),
            ('promoted', str),
            ('position', str),
            ('vote_sum', str),
            ('vote_count', str),
            ('section_id', str),
            ('created_at', str),
            ('updated_at', str),
            ('name', str),
            ('title', str),
            ('source_locale', str),
            ('locale', str),
            ('outdated', str),
            ('outdated_locales', str),
            ('edited_at', str),
            ('user_segment_id', str),
            ('permission_group_id', str),
            ('label_names', str),
            ('body', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('url', str),
            ('html_url', str),
            ('author_id', str),
            ('comments_disabled', str),
            ('draft', str),
            ('promoted', str),
            ('position', str),
            ('vote_sum', str),
            ('vote_count', str),
            ('section_id', str),
            ('created_at', str),
            ('updated_at', str),
            ('name', str),
            ('title', str),
            ('source_locale', str),
            ('locale', str),
            ('outdated', str),
            ('outdated_locales', str),
            ('edited_at', str),
            ('user_segment_id', str),
            ('permission_group_id', str),
            ('label_names', str),
            ('body', str)
        ])

        self._move_to_clean(
            table_name=table_name,
            key='clean/zendesk/articles/dt_extraction={dt}/{dt}.parquet'.format(dt=self.execution_date),
            query=query.format(dt=self.execution_date),
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def group_memberships(self, table_name):
        query = BaseETL.get_query_from_file_name('{}/zendesk/group_memberships.sql'
                                                 .format(DATALAKE_QUERIES_DIR))

        r_cols = OrderedDict([
            ('url', str),
            ('id', str),
            ('user_id', str),
            ('group_id', str),
            ('default', str),
            ('created_at', str),
            ('updated_at', str)
        ])

        c_cols = OrderedDict([
            ('url', str),
            ('id', str),
            ('user_id', str),
            ('group_id', str),
            ('default', str),
            ('created_at', str),
            ('updated_at', str)
        ])

        self._move_to_clean(
            table_name=table_name,
            key='clean/zendesk/group_memberships/dt_extraction={dt}/{dt}.parquet'.format(dt=self.execution_date),
            query=query.format(dt=self.execution_date),
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean(self, table_name, key, query, r_cols, c_cols=None):
        empty = self._is_clean_table_empty(table_name)

        if not empty:
            query = "{} \n where dt='{}'".format(query, self.execution_date)

            self.athena_client.add_partition(
                database=ZendeskETL.SCHEMAS['raw'],
                table_name="zendesk_{}".format(table_name),
                partition="dt='{}'".format(self.execution_date)
            )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query,
            raw_columns=r_cols,
            clean_columns=c_cols
        )

        self.athena_client.add_partition(
            database=ZendeskETL.SCHEMAS['clean'],
            table_name="zendesk_{}".format(table_name),
            partition="dt_extraction='{}'".format(self.execution_date)
        )

    @logger
    def _is_clean_table_empty(self, table_name):
        result = self.athena_client.execute_query_and_return_dataframe(
            "select 1 from {}.zendesk_{} limit 1".format(ZendeskETL.SCHEMAS['clean'], table_name))

        empty = len(result) == 0

        logger.info("m=_is_clean_table_empty, table={}, empty={}"
                    .format(table_name, empty))

        return empty

    @logger
    def build_staging_table(self, table_name):
        query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/zendesk/{file_name}.sql'.format(
                query_base_dir=DATALAKE_QUERIES_DIR,
                file_name=table_name))

        empty = self._is_prod_table_empty(table_name)
        logger.info('m=build_staging_table, table_name={}, empty={}'.format(table_name, empty))
        if not empty:
            logger.info(
                'm=build_staging_table, table_name={}, msg=production table is not empty'.format(
                    table_name))
            where_clause = "where t.dt_extraction='{}'".format(self.execution_date)
            query = query.replace(ZendeskETL.WHERE_CLAUSE, where_clause)
        else:
            query.replace(ZendeskETL.WHERE_CLAUSE, '')

        df = self.athena_client.execute_query_and_return_dataframe(query)
        table_data = petl.fromdataframe(df)

        BaseETL.bulk_insert(
            table=table_data,
            table_name='staging.zendesk_{}'.format(table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=False,
            commit=True
        )

    @logger
    def build_prod_table(self, table_name):
        upsert_query = "SELECT * FROM staging.zendesk_{}".format(table_name)

        delete_query = BaseETL.get_query_from_file_name(
            '{query_base_dir}/zendesk/delete_old_entries.sql'.format(
                query_base_dir=DW_QUERIES_DIR))

        empty = self._is_prod_table_empty(table_name)
        if empty:
            logger.info(
                'm=build_staging_table, schema=staging, table_name={}, msg=production table is empty, executing first load!'.format(
                    table_name))
        else:
            self._delete_old_entries(
                delete_query.format(table_name=table_name, sk_field=ZendeskETL.SK_FIELDS[table_name]))

            if table_name.split("_")[0] == 'fact':
                upsert_query = "{} \nwhere sk_extraction_date = {};".format(upsert_query,
                                                                            self.execution_datetime.strftime('%Y%m%d'))

        self._upsert_data(upsert_query, table_name)

    @logger(exclude='df')
    def _upsert_data(self, upsert_query, table_name):
        logger.info(
            'm=_upsert_data, table_name={}, msg=getting data from DW, query={}'.format(table_name,
                                                                                       upsert_query))

        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=upsert_query,
            encoding='utf-8',
        )

        logger.info(
            '_upsert_data, table_name={}, msg=bulk inserting...'.format(table_name))

        BaseETL.bulk_insert(
            table=table_data,
            table_name='zendesk.{}'.format(table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8',
            append=True,
            commit=True
        )

        logger.info(
            'm=_upsert_data, table_name={}, msg=ready to read data!'.format(table_name))

    @logger
    def _is_prod_table_empty(self, table_name):
        result = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query="select 1 from zendesk.{} limit 1".format(table_name),
            encoding='utf-8'
        )

        return len(result) == 1

    @logger
    def _delete_old_entries(self, delete_query):
        BaseETL.execute_command(
            db_enum=EnumDB.BI_DW,
            command=delete_query,
            commit=True,
            encoding='utf-8'
        )
