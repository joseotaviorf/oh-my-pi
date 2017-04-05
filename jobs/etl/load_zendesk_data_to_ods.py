# coding=utf-8
import json
import sys
from datetime import datetime

import boto3
from jobs.base.base_etl import BaseETL, EnumDb


class ZendeskDataToODS(object):
    def __init__(self, args):
        self.object_type = args[1]
        self.start_time = int(datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S').strftime('%s'))
        self.s3_bucket = args[3]
        self.ods_schema = args[4]
        self.s3 = boto3.client('s3')

        self.db_enum = EnumDb.BI_ODS

        print 'c=ZendeskDataToODS, object_type={}, start_time={}, s3_bucket={}, ods_schema={}, db_enum={}'.format(
            self.object_type,
            self.start_time,
            self.s3_bucket,
            self.ods_schema,
            self.db_enum)

        self.ods_conn = BaseETL.get_connection(db_enum=self.db_enum, encoding='UTF-8')

    def __load_files_from_bucket(self):
        return self.s3.list_objects_v2(Bucket=self.s3_bucket, Prefix='{}/{}'.format(self.object_type, self.start_time))

    def save_s3_data_to_ods(self):
        print 'm=save_s3_data_to_ods, init'

        files = self.__load_files_from_bucket()
        for i in range(0, len(files['Contents'])):
            s3_object = self.s3.get_object(Bucket=self.s3_bucket, Key=files['Contents'][i]['Key'])
            file_content = json.loads(s3_object['Body'].read().decode('utf-8'))

            if self.object_type == 'ticket':
                self.upsert_tickets(file_content['tickets'])
            elif self.object_type == 'ticket_metrics':
                self.upsert_ticket_metrics(file_content['ticket_metrics'])
            elif self.object_type == 'user':
                self.upsert_users(file_content['users'])
            elif self.object_type == 'group_membership':
                self.upsert_group_memberships(file_content['group_memberships'])
            elif self.object_type == 'group':
                self.upsert_groups(file_content['groups'])
            else:
                return

    def __execute_command(self, command, return_value=False):
        command = str(command).replace("'null'", "null")
        return BaseETL.execute_command(command=command, db_enum=self.db_enum, conn=self.ods_conn, encoding='UTF-8',
                                       commit=True, return_value=return_value)

    def __check_existence(self, field, dict_var):
        return 'null' if field not in dict_var else BaseETL.coalesce(dict_var[field])

    def upsert_groups(self, groups):
        print 'upsert_groups, init'
        count = 0
        for g in groups:
            print 'processing group [id={}]'.format(g['id'])

            count += 1
            upsert_groups_command = " insert into {}.group (id, url, \"name\", deleted, created_at, updated_at) " \
                                    " values ('{}','{}','{}',{},'{}','{}') on conflict (id) do update set " \
                                    " url = excluded.url, \"name\" = excluded.\"name\", " \
                                    " deleted = excluded.deleted, created_at = excluded.created_at, " \
                                    " updated_at = excluded.updated_at ".format(self.ods_schema,
                                                                                g['id'],
                                                                                g['url'],
                                                                                g['name'].encode('utf-8'),
                                                                                g['deleted'],
                                                                                BaseETL.format_date(g['created_at']),
                                                                                BaseETL.format_date(g['updated_at'])
                                                                                )

            self.__execute_command(command=upsert_groups_command)
        print 'upsert_groups, end, count: {}'.format(count)

    def upsert_group_memberships(self, group_memberships):
        print 'upsert_group_memberships, init'
        count = 0
        for gm in group_memberships:
            print 'processing group_memberships [id={}]'.format(gm['id'])

            count += 1
            upsert_group_memberships_command = " insert into {}.group_membership (id, url, user_id, group_id, " \
                                               " \"default\", created_at, updated_at) values ('{}','{}','{}','{}'," \
                                               " {},'{}','{}') on conflict (id) do update set " \
                                               " url = excluded.url, user_id = excluded.user_id, group_id = excluded.group_id, " \
                                               " \"default\" = excluded.\"default\", created_at = excluded.created_at, " \
                                               " updated_at = excluded.updated_at ".format(self.ods_schema,
                                                                                           gm['id'],
                                                                                           gm['url'],
                                                                                           gm['user_id'],
                                                                                           gm['group_id'],
                                                                                           gm['default'],
                                                                                           BaseETL.format_date(
                                                                                               gm['created_at']),
                                                                                           BaseETL.format_date(
                                                                                               gm['updated_at'])
                                                                                           )

            self.__execute_command(command=upsert_group_memberships_command)

        print 'upsert_group_memberships, end, count: {}'.format(count)

    def upsert_users(self, users):
        print 'upsert_users, init'
        count = 0
        for u in users:
            print 'processing user [id={}]'.format(u['id'])

            count += 1
            if u['tags'] and len(u['tags']) > 0:
                delete_user_tags_command = " delete from {}.tag where object_id = '{}' ".format(self.ods_schema,
                                                                                                u['id'])
                self.__execute_command(command=delete_user_tags_command)

                for tag in u['tags']:
                    upsert_user_tags_command = " insert into {}.tag (object_id, \"value\") " \
                                               " values ('{}','{}') ".format(self.ods_schema,
                                                                             u['id'],
                                                                             BaseETL.coalesce(tag.encode('utf-8')
                                                                                              if tag else None)
                                                                             )
                    self.__execute_command(command=upsert_user_tags_command)

            if u['user_fields']:
                delete_user_fields_command = " delete from {}.user_fields where user_id = '{}' ".format(
                    self.ods_schema,
                    u['id'])
                self.__execute_command(command=delete_user_fields_command)

                for uf in u['user_fields']:
                    user_field_value = None
                    if isinstance(u['user_fields'][uf], (str, unicode)):
                        user_field_value = u['user_fields'][uf].encode('utf-8')
                    if isinstance(u['user_fields'][uf], (bool, int)):
                        user_field_value = u['user_fields'][uf]

                    upsert_user_fields_command = " insert into {}.user_fields (user_id, description, \"value\") " \
                                                 " values ('{}','{}','{}') ".format(self.ods_schema,
                                                                                    u['id'],
                                                                                    uf.encode('utf-8'),
                                                                                    BaseETL.coalesce(user_field_value)
                                                                                    )
                    self.__execute_command(command=upsert_user_fields_command)

            photo_id = None
            delete_user_photo_command = " delete from {}.attachment where user_id = '{}' ".format(
                self.ods_schema,
                u['id'])
            self.__execute_command(command=delete_user_photo_command)

            if u['photo']:
                user_photo = u['photo']

                thumbnail_url = None
                if user_photo['thumbnails'] and len(user_photo['thumbnails']) > 0:
                    thumbnail_url = user_photo['thumbnails'][0]['content_url']

                file_name = None
                if 'name' in user_photo:
                    file_name = user_photo['name']
                elif 'file_name' in user_photo:
                    file_name = user_photo['file_name']

                upsert_user_photo_command = " insert into {}.attachment (user_id, file_name, content_url, content_type, " \
                                            " \"size\", inline, thumbnail_url) values ('{}','{}','{}','{}',{},{},'{}') " \
                                            " on conflict (user_id) do update set file_name = excluded.file_name, " \
                                            " content_url = excluded.content_url, content_type = excluded.content_type, " \
                                            " \"size\" = excluded.size, inline = excluded.inline, " \
                                            " thumbnail_url = excluded.thumbnail_url returning id ".format(
                    self.ods_schema,
                    u['id'],
                    BaseETL.coalesce(file_name),
                    BaseETL.coalesce(user_photo['content_url']),
                    BaseETL.coalesce(user_photo['content_type']),
                    BaseETL.coalesce(user_photo['size']),
                    BaseETL.coalesce(user_photo['inline']),
                    BaseETL.coalesce(thumbnail_url)
                )

                photo_id = self.__execute_command(command=upsert_user_photo_command, return_value=True)

            upsert_user_command = " insert into {}.user (id, email, \"name\", active, alias, chat_only, created_at, " \
                                  " custom_role_id, details, external_id, last_login_at, locale, locale_id, moderator, " \
                                  " notes, only_private_comments, organization_id, default_group_id, phone, photo_id, " \
                                  " restricted_agent, role, shared, shared_agent, signature, suspended, " \
                                  " ticket_restriction, time_zone, two_factor_auth_enabled, updated_at, url, " \
                                  " verified) values ('{}','{}','{}',{},'{}',{},'{}'," \
                                  " {},'{}',{},'{}','{}',{},{}," \
                                  " '{}',{},'{}',{},'{}',{}," \
                                  " {},'{}',{},{},'{}',{}," \
                                  " '{}','{}',{},'{}','{}',{}) on conflict (id) do update set " \
                                  " id = excluded.id, email = excluded.email, \"name\" = excluded.\"name\", " \
                                  " active = excluded.active, alias = excluded.alias, chat_only = excluded.chat_only, " \
                                  " created_at = excluded.created_at, custom_role_id = excluded.custom_role_id, " \
                                  " details = excluded.details, external_id = excluded.external_id, " \
                                  " last_login_at = excluded.last_login_at, locale = excluded.locale, " \
                                  " locale_id = excluded.locale_id, moderator = excluded.moderator, " \
                                  " notes = excluded.notes, only_private_comments = excluded.only_private_comments, " \
                                  " organization_id = excluded.organization_id, " \
                                  " default_group_id = excluded.default_group_id, phone = excluded.phone, " \
                                  " photo_id = excluded.photo_id, restricted_agent = excluded.restricted_agent, " \
                                  " role = excluded.role, shared = excluded.shared, " \
                                  " shared_agent = excluded.shared_agent, signature = excluded.signature, " \
                                  " suspended = excluded.suspended, ticket_restriction = excluded.ticket_restriction, " \
                                  " time_zone = excluded.time_zone, " \
                                  " two_factor_auth_enabled = excluded.two_factor_auth_enabled, " \
                                  " updated_at = excluded.updated_at, url = excluded.url, " \
                                  " verified = excluded.verified ".format(self.ods_schema,
                                                                          u['id'],
                                                                          BaseETL.coalesce(None if not u['email']
                                                                                           else u['email']
                                                                                           .encode('utf-8')
                                                                                           .replace('"', '""')
                                                                                           .replace("'", "''")
                                                                                           ),
                                                                          BaseETL.coalesce(None if not u['name']
                                                                                           else u['name']
                                                                                           .encode('utf-8')
                                                                                           .replace('"', '""')
                                                                                           .replace("'", "''")
                                                                                           ),
                                                                          BaseETL.coalesce(u['active']),
                                                                          BaseETL.coalesce(
                                                                              u['alias']).encode(
                                                                              'utf-8'),
                                                                          u['chat_only'],
                                                                          BaseETL.format_date(
                                                                              u['created_at']),
                                                                          BaseETL.coalesce(
                                                                              u['custom_role_id']),
                                                                          BaseETL.coalesce(
                                                                              u['details']).encode(
                                                                              'utf-8'),
                                                                          BaseETL.coalesce(
                                                                              u['external_id']),
                                                                          BaseETL.format_date(
                                                                              u['last_login_at']),
                                                                          BaseETL.coalesce(
                                                                              u['locale']),
                                                                          BaseETL.coalesce(
                                                                              u['locale_id']),
                                                                          BaseETL.coalesce(u['moderator']),
                                                                          BaseETL.coalesce(u['notes']),
                                                                          u['only_private_comments'],
                                                                          BaseETL.coalesce(
                                                                              u['organization_id']),
                                                                          self.__check_existence(
                                                                              field='default_group_id',
                                                                              dict_var=u),
                                                                          BaseETL.coalesce(u['phone']),
                                                                          BaseETL.coalesce(photo_id),
                                                                          BaseETL.coalesce(u['restricted_agent']),
                                                                          BaseETL.coalesce(u['role']),
                                                                          BaseETL.coalesce(u['shared']),
                                                                          BaseETL.coalesce(u['shared_agent']),
                                                                          BaseETL.coalesce(u['signature']),
                                                                          BaseETL.coalesce(u['suspended']),
                                                                          BaseETL.coalesce(
                                                                              u['ticket_restriction']),
                                                                          u['time_zone'].encode(
                                                                              'utf-8'),
                                                                          BaseETL.coalesce(
                                                                              u['two_factor_auth_enabled']),
                                                                          BaseETL.format_date(u['updated_at']),
                                                                          BaseETL.coalesce(u['url']),
                                                                          BaseETL.coalesce(u['verified'])
                                                                          )
            self.__execute_command(command=upsert_user_command)

        print 'upsert_users, end, count: {}'.format(count)

    def upsert_ticket_metrics(self, ticket_metrics):
        print 'upsert_ticket_metrics, init'
        count = 0
        for tm in ticket_metrics:
            print 'processing ticket_metrics [id={}]'.format(tm['id'])
            count += 1
            upsert_ticket_metrics_command = " insert into {}.ticket_metrics (id, ticket_id, url, group_stations, " \
                                            " assignee_stations, reopens, replies, assignee_updated_at, " \
                                            " requester_updated_at, status_updated_at, initially_assigned_at, " \
                                            " assigned_at, solved_at, latest_comment_added_at, " \
                                            " first_resolution_time_in_minutes_calendar, first_resolution_time_in_minutes_business, " \
                                            " agent_wait_time_in_minutes_calendar, agent_wait_time_in_minutes_business, " \
                                            " requester_wait_time_in_minutes_calendar, requester_wait_time_in_minutes_business, " \
                                            " created_at, updated_at) " \
                                            " values ('{}','{}','{}',{}, " \
                                            " {},{},{},'{}', " \
                                            " '{}','{}','{}', " \
                                            " '{}','{}','{}', " \
                                            " {},{}, " \
                                            " {},{}, " \
                                            " {},{}, " \
                                            " '{}','{}') on conflict (id) do update set " \
                                            " ticket_id = excluded.ticket_id, url = excluded.url, " \
                                            " group_stations = excluded.group_stations, assignee_stations = excluded.assignee_stations, " \
                                            " reopens = excluded.reopens, replies = excluded.replies, " \
                                            " assignee_updated_at = excluded.assignee_updated_at, " \
                                            " requester_updated_at = excluded.requester_updated_at, " \
                                            " status_updated_at = excluded.status_updated_at, " \
                                            " initially_assigned_at = excluded.initially_assigned_at, " \
                                            " assigned_at = excluded.assigned_at, solved_at = excluded.solved_at, " \
                                            " latest_comment_added_at = excluded.latest_comment_added_at, " \
                                            " first_resolution_time_in_minutes_calendar = excluded.first_resolution_time_in_minutes_calendar, " \
                                            " first_resolution_time_in_minutes_business = excluded.first_resolution_time_in_minutes_business, " \
                                            " agent_wait_time_in_minutes_calendar = excluded.agent_wait_time_in_minutes_calendar, " \
                                            " agent_wait_time_in_minutes_business = excluded.agent_wait_time_in_minutes_business, " \
                                            " requester_wait_time_in_minutes_calendar = excluded.requester_wait_time_in_minutes_calendar, " \
                                            " requester_wait_time_in_minutes_business = excluded.requester_wait_time_in_minutes_business, " \
                                            " created_at = excluded.created_at, updated_at = excluded.updated_at".format(
                self.ods_schema,
                tm['id'],
                tm['ticket_id'],
                BaseETL.coalesce(tm['url']),
                BaseETL.coalesce(tm['group_stations']),
                BaseETL.coalesce(tm['assignee_stations']),
                BaseETL.coalesce(tm['reopens']),
                BaseETL.coalesce(tm['replies']),
                BaseETL.format_date(tm['assignee_updated_at']),
                BaseETL.format_date(tm['requester_updated_at']),
                BaseETL.format_date(tm['status_updated_at']),
                BaseETL.format_date(tm['initially_assigned_at']),
                BaseETL.format_date(tm['assigned_at']),
                BaseETL.format_date(tm['solved_at']),
                BaseETL.format_date(tm['latest_comment_added_at']),
                BaseETL.coalesce(tm['first_resolution_time_in_minutes']['calendar']),
                BaseETL.coalesce(tm['first_resolution_time_in_minutes']['business']),
                BaseETL.coalesce(tm['agent_wait_time_in_minutes']['calendar']),
                BaseETL.coalesce(tm['agent_wait_time_in_minutes']['business']),
                BaseETL.coalesce(tm['requester_wait_time_in_minutes']['calendar']),
                BaseETL.coalesce(tm['requester_wait_time_in_minutes']['business']),
                BaseETL.format_date(tm['created_at']),
                BaseETL.format_date(tm['updated_at'])
            )

            self.__execute_command(command=upsert_ticket_metrics_command)

        print 'upsert_ticket_metrics, end, count: {}'.format(count)

    def upsert_tickets(self, tickets):
        print 'upsert_tickets, init'
        count = 0
        for t in tickets:
            print 'processing ticket [id={}]'.format(t['id'])
            count += 1

            delete_via_command = " delete from {}.via where object_id = '{}' ".format(self.ods_schema, t['id'])
            self.__execute_command(command=delete_via_command)

            upsert_via_command = " insert into {}.via (channel, object_id) values ('{}','{}') " \
                                 " on conflict (object_id) do update set channel = excluded.channel, " \
                                 " object_id = excluded.object_id returning id ".format(
                self.ods_schema, t['via']['channel'], t['id'])

            via_id = self.__execute_command(command=upsert_via_command, return_value=True)

            if len(t['via']['source']['to']) > 0 or len(t['via']['source']['from']) > 0 or t['via']['source']['rel']:
                delete_source_command = " delete from {}.source where via_id = {} ".format(self.ods_schema, via_id)
                self.__execute_command(command=delete_source_command)

                upsert_source_command = " insert into {}.source (\"to\", \"from\", rel, via_id) " \
                                        " values ('{}','{}','{}', {}) returning id ".format(self.ods_schema,
                                                                                            json.dumps(
                                                                                                t['via']['source'][
                                                                                                    'to']).encode(
                                                                                                'utf-8').replace("'",
                                                                                                                 "''"),
                                                                                            json.dumps(
                                                                                                t['via']['source'][
                                                                                                    'from']).encode(
                                                                                                'utf-8').replace("'",
                                                                                                                 "''"),
                                                                                            'null' if not
                                                                                            t['via']['source'][
                                                                                                'rel'] else
                                                                                            t['via']['source']['rel'],
                                                                                            via_id)
                source_id = self.__execute_command(command=upsert_source_command, return_value=True)
                self.__execute_command(
                    command=" update {}.via set source_id = {} where id = {} ".format(self.ods_schema, source_id,
                                                                                      via_id))

            if t['custom_fields']:
                delete_custom_fields_command = " delete from {}.custom_fields where object_id = '{}' ".format(
                    self.ods_schema,
                    t['id'])
                self.__execute_command(command=delete_custom_fields_command)

                for cf in t['custom_fields']:
                    custom_field_value = None
                    if isinstance(cf['value'], (str, unicode)):
                        custom_field_value = cf['value'].encode('utf-8')
                    if isinstance(cf['value'], (bool, int, long)):
                        custom_field_value = cf['value']

                    upsert_custom_fields_command = " insert into {}.custom_fields (id, object_id, \"value\") " \
                                                   " values ('{}','{}','{}') on conflict (id, object_id) do update set " \
                                                   "\"value\" = excluded.\"value\" ".format(self.ods_schema,
                                                                                            cf['id'],
                                                                                            t['id'],
                                                                                            BaseETL.coalesce(
                                                                                                custom_field_value)
                                                                                            )
                    self.__execute_command(command=upsert_custom_fields_command)

            if t['fields']:
                delete_ticket_fields_command = " delete from {}.ticket_fields where ticket_id = '{}' ".format(
                    self.ods_schema,
                    t['id'])
                self.__execute_command(command=delete_ticket_fields_command)

                for f in t['fields']:
                    field_value = None
                    if isinstance(f['value'], (str, unicode)):
                        field_value = f['value'].encode('utf-8')
                    if isinstance(f['value'], (bool, int, long)):
                        field_value = f['value']

                    upsert_ticket_fields_command = " insert into {}.ticket_fields (id, ticket_id, \"value\") " \
                                                   " values ('{}','{}','{}') on conflict (id, ticket_id) do update set " \
                                                   "\"value\" = excluded.\"value\" ".format(self.ods_schema,
                                                                                            f['id'],
                                                                                            t['id'],
                                                                                            BaseETL.coalesce(
                                                                                                field_value)
                                                                                            )
                    self.__execute_command(command=upsert_ticket_fields_command)

            if t['tags'] and len(t['tags']) > 0:
                delete_ticket_tags_command = " delete from {}.tag where object_id = '{}' ".format(self.ods_schema,
                                                                                                  t['id'])
                self.__execute_command(command=delete_ticket_tags_command)

                for tag in t['tags']:
                    upsert_ticket_tags_command = " insert into {}.tag (object_id, \"value\") " \
                                                 " values ('{}','{}') ".format(self.ods_schema,
                                                                               t['id'],
                                                                               BaseETL.coalesce(
                                                                                   tag.encode(
                                                                                       'utf-8') if tag else None)
                                                                               )
                    self.__execute_command(command=upsert_ticket_tags_command)

            if t['collaborator_ids'] and len(t['collaborator_ids']) > 0:
                delete_collaborator_ids_command = " delete from {}.object_collaborators where object_id = '{}' ".format(
                    self.ods_schema,
                    t['id'])
                self.__execute_command(command=delete_collaborator_ids_command)

                for ci in t['collaborator_ids']:
                    upsert_collaborator_ids_command = " insert into {}.object_collaborators (object_id, collaborator_id) " \
                                                      " values ('{}','{}') ".format(self.ods_schema, t['id'], ci)

                    self.__execute_command(command=upsert_collaborator_ids_command)

            upsert_ticket_command = " insert into {}.ticket (id, url, external_id,\"type\", subject, raw_subject," \
                                    " description,priority, status, recipient, requester_id, submitter_id, assignee_id," \
                                    " organization_id, group_id, forum_topic_id, problem_id, has_incidents," \
                                    " via_id,  ticket_form_id, brand_id, allow_channelback, is_public, created_at, " \
                                    " updated_at, due_at, followup_ids, sharing_agreement_ids, satisfaction_rating_score, " \
                                    " satisfaction_rating_comment) " \
                                    " values ('{}', '{}', '{}', '{}','{}','{}'," \
                                    " '{}','{}','{}','{}',{},{},{}," \
                                    " '{}','{}','{}','{}',{}," \
                                    " {},'{}','{}'," \
                                    " {},{},'{}','{}','{}','{}','{}', '{}', '{}') " \
                                    " on conflict (id) do update set " \
                                    " url = excluded.url, external_id = excluded.external_id,\"type\" = excluded.\"type\", " \
                                    "subject = excluded.subject, raw_subject = excluded.raw_subject," \
                                    " description = excluded.description,priority = excluded.priority, " \
                                    " status = excluded.status, recipient = excluded.recipient, " \
                                    " requester_id = excluded.requester_id, submitter_id = excluded.submitter_id, " \
                                    "assignee_id = excluded.assignee_id, organization_id = excluded.organization_id, " \
                                    " group_id = excluded.group_id, forum_topic_id = excluded.forum_topic_id," \
                                    " problem_id = excluded.problem_id, has_incidents = excluded.has_incidents," \
                                    " via_id = excluded.via_id,  ticket_form_id = excluded.ticket_form_id, " \
                                    " brand_id = excluded.brand_id, allow_channelback = excluded.allow_channelback, " \
                                    " is_public = excluded.is_public, created_at = excluded.created_at, " \
                                    " updated_at = excluded.updated_at,due_at = excluded.due_at, " \
                                    " followup_ids = excluded.followup_ids, " \
                                    " sharing_agreement_ids = excluded.sharing_agreement_ids, " \
                                    " satisfaction_rating_score = excluded.satisfaction_rating_score, " \
                                    " satisfaction_rating_comment = excluded.satisfaction_rating_comment ".format(
                self.ods_schema,
                t['id'],
                BaseETL.coalesce(t['url']),
                BaseETL.coalesce(t['external_id']),
                BaseETL.coalesce(t['type']),
                BaseETL.coalesce(t['subject'].encode('utf-8').replace("'", "''") if t['subject'] else None),
                BaseETL.coalesce(t['raw_subject'].encode('utf-8').replace("'", "''") if t['raw_subject'] else None),
                BaseETL.coalesce(t['description'].encode('utf-8').replace("'", "''") if t['description'] else None),
                BaseETL.coalesce(t['priority']),
                BaseETL.coalesce(t['status']),
                BaseETL.coalesce(t['recipient']),
                BaseETL.coalesce(t['requester_id']),
                BaseETL.coalesce(t['submitter_id']),
                BaseETL.coalesce(t['assignee_id']),
                BaseETL.coalesce(t['organization_id']),
                BaseETL.coalesce(t['group_id']),
                BaseETL.coalesce(t['forum_topic_id']),
                BaseETL.coalesce(t['problem_id']),
                BaseETL.coalesce(t['has_incidents']),
                BaseETL.coalesce(via_id),
                BaseETL.coalesce(t['ticket_form_id']),
                BaseETL.coalesce(t['brand_id']),
                BaseETL.coalesce(t['allow_channelback']),
                BaseETL.coalesce(t['is_public']),
                BaseETL.format_date(t['created_at']),
                BaseETL.format_date(t['updated_at']),
                BaseETL.format_date(t['due_at']),
                str(self.__check_existence(field='followup_ids', dict_var=t)).replace('[', '{').replace(']', '}'),
                str(self.__check_existence(field='sharing_agreement_ids', dict_var=t)).replace('[', '{').replace(']',
                                                                                                                 '}'),
                'null' if self.__check_existence(field='score',
                                                 dict_var=t['satisfaction_rating']) == 'null' else BaseETL.coalesce(
                    t['satisfaction_rating']['score']),
                'null' if self.__check_existence(field='comment',
                                                 dict_var=t['satisfaction_rating']) == 'null' else BaseETL.coalesce(
                    t['satisfaction_rating']['comment'].encode('utf-8') if t['satisfaction_rating'][
                        'comment'] else None)
            )

            self.__execute_command(command=upsert_ticket_command)

        print 'upsert_tickets, end, count: {}'.format(count)


if __name__ == '__main__':
    args = sys.argv
    print 'START'
    zendesk_data_to_ods = ZendeskDataToODS(args)
    zendesk_data_to_ods.save_s3_data_to_ods()
    print 'END'
    sys.stdout.flush()
