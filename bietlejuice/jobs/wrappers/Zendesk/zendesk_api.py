import logging
import requests
import json
import pandas as pd
from datetime import datetime
from zenpy import Zenpy


class ZendeskAPI(object):
    def __init__(self, object_type,
                 client_id, client_secret,
                 start_time, end_time=None,
                 chat_client_id=None, chat_client_secret=None, chat_token=None,
                 subdomain='quintoandar'):
        self.object_type = object_type
        self.zenpy_client = self.__get_zendek_client(
            client_id=client_id,
            client_secret=client_secret,
            subdomain=subdomain
        )
        self.chat_client = self.__get_chat_client(
            client_id=chat_client_id,
            client_secret=chat_client_secret,
            auth_token=chat_token,
            subdomain=subdomain
        )
        self.start_time = start_time
        self.end_time = end_time
        self.human_start_time = datetime.fromtimestamp(self.start_time).strftime('%Y-%m-%d')
        self.human_end_time = datetime.fromtimestamp(self.end_time).strftime('%Y-%m-%d')

    @classmethod
    def __get_zendek_client(cls, client_id, client_secret, subdomain='quintoandar'):
        payload_zendesk = {
            'grant_type': 'client_credentials',
            'client_id': client_id,
            'client_secret': client_secret,
            'scope': 'read',
        }

        response_zen = requests.post(
            "https://{}.zendesk.com/oauth/tokens".format(subdomain),
            data=payload_zendesk).json()
        creds_zen = {
            "subdomain": "quintoandar",
            "oauth_token": response_zen.get('access_token')
        }
        return Zenpy(**creds_zen)

    @classmethod
    def __get_chat_client(cls, client_id, client_secret, auth_token,
                          subdomain='quintoandar', name='Data Team - Confidential Client'):
        if not client_id or not client_secret or not auth_token:
            return None

        json = {
            "name": name,
            "company": "QuintoAndar",
            "client_secret": client_secret,
            "client_identifier": client_id,
            "client_type": "confidential",
            "redirect_uris": "https://localhost:5000/autorize",
            "scopes": "read write"
        }
        headers = {
            "Authorization": "Bearer {}".format(auth_token)
        }

        # TODO: Change DELETE/CREATE to UPDATE an existing Confidential Client
        url_clients = 'https://www.zopim.com/api/v2/oauth/clients'
        response_list = requests.get(url_clients, json=json, headers=headers).json()
        df = pd.DataFrame.from_dict(response_list)
        frame_to_delete = df.loc[df['name'] == name]
        if not frame_to_delete.empty:
            for item in frame_to_delete.to_records():
                id = item['id']
                requests.delete("{}/{}".format(url_clients, id), json=json, headers=headers)
        response_creation = requests.post(url_clients, json=json, headers=headers).json()

        payload_chat = {
            'grant_type': 'client_credentials',
            "client_type": response_creation.get('client_type'),
            'client_id': response_creation.get('client_identifier'),
            'client_secret': response_creation.get('client_secret'),
            'redirect_uri': response_creation.get('redirect_uris')
        }

        response_chat = requests.post(
            "https://www.zopim.com/oauth2/token",
            params=payload_chat
        ).json()
        creds_chat = {
            "subdomain": subdomain,
            "oauth_token": response_chat.get('access_token')
        }
        return Zenpy(**creds_chat)

    def __get_tickets_data(self):
        return self.__get_incremental_data(zendesk_object=self.zenpy_client.tickets)

    def __get_chats_data(self, batch_limit=50):
        search_clause = 'timestamp:[{} TO {}]'.format(self.human_start_time, self.human_end_time)
        logging.info('m=__get_chats_data ({}), init'.format(search_clause))
        result_search = self.chat_client.chats.search(search_clause)
        result_search = self.__do_all_pages(result=result_search, key_timestamp='timestamp')

        # with result_search, get chat by chat!
        URL = 'https://www.zopim.com/api/v2/chats?ids={}'
        result = []
        ids = []
        for item in result_search:
            ids.append(item['id'])
            if len(ids) == batch_limit or result_search[-1] == item:  # batch limit or last item
                str_ids = ','.join(ids)
                url_request = URL.format(str_ids)
                logging.info('m=__get_chat (id: {}), init'.format(str_ids))
                chats = self.chat_client.chats._get(url_request, True).json().get('docs')
                for id in chats:
                    result.append(chats[id])
                ids = []
        return result

    def __get_ticket_fields_type_data(self):
        logging.info('m=get_ticket_fields_type_data, init')
        result = self.zenpy_client.ticket_fields()
        return self.__do_all_pages(result)

    def __get_ticket_metrics_data(self):
        logging.info('m=get_ticket_metrics_data, init')
        result = self.zenpy_client.ticket_metrics()
        return self.__do_all_pages(result)

    def __get_satisfaction_ratings_data(self):
        logging.info('m=get_satisfaction_ratings_data, init')
        result = self.zenpy_client.satisfaction_ratings(sort_order='asc')
        return self.__do_all_pages(result)

    def __get_requests_data(self):
        logging.info('m=get_requests_data, init')
        result = self.zenpy_client.requests()
        return self.__do_all_pages(result)

    def __get_groups_data(self):
        logging.info('m=get_groups_data, init')
        result = self.zenpy_client.groups()
        return self.__do_all_pages(result)

    def __get_group_memberships_data(self):
        logging.info('m=get_group_memberships_data, init')
        result = self.zenpy_client.group_memberships()
        return self.__do_all_pages(result)

    def __get_users_data(self):
        return self.__get_incremental_data(zendesk_object=self.zenpy_client.users)

    def __get_search_data(self, zendesk_object):
        logging.info('m=__get_search_data, zendesk_object={}, start_time={}'.format(zendesk_object, self.start_time))
        return zendesk_object.search(updated_after=datetime.fromtimestamp(self.start_time).__format__('%Y-%m-%d'),
                                     type=zendesk_object)

    def __get_incremental_data(self, zendesk_object):
        logging.info(
            'm=__get_incremental_data, zendesk_object={}, start_time={}'.format(zendesk_object, self.start_time))
        incremental_data_result = zendesk_object.incremental(start_time=self.start_time)
        return self.__do_all_pages(incremental_data_result, True)

    def __do_all_pages(self, result, incremental=False, key_timestamp='updated_at'):
        response = []
        while True:
            try:
                r = result._response_json
                items = r.get(self.object_type) or r.get('results')
                if not items:
                    return None

                for item in items:
                    updated_at = int(datetime.strptime(item.get(key_timestamp), '%Y-%m-%dT%H:%M:%SZ').strftime('%s'))
                    if not incremental or not item.get(key_timestamp) or self.start_time <= updated_at <= self.end_time:
                        response.append(item)
                if (r.get('end_time') and r.get('end_time') <= self.end_time) or r.get('next_page') or r.get('next_url'):
                    result.handle_pagination()
                else:
                    return response
            except StopIteration:
                return response
            except Exception as e:
                print(e)
                raise

    def get_data(self):
        result = None
        partition = None
        if self.object_type == 'tickets':
            result = self.__get_tickets_data()
        elif self.object_type == 'users':
            result = self.__get_users_data()
        elif self.object_type == 'ticket_metrics':
            result = self.__get_ticket_metrics_data()
        elif self.object_type == 'groups':
            result = self.__get_groups_data()
        elif self.object_type == 'group_memberships':
            result = self.__get_group_memberships_data()
        elif self.object_type == 'ticket_fields_type':
            result = self.__get_ticket_fields_type_data()
        elif self.object_type == 'chats':
            result = self.__get_chats_data()

        return result
