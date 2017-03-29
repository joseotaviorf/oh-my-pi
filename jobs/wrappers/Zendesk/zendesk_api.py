import logging

from zenpy import Zenpy


class ZendeskAPI(object):
    def __init__(self, subdomain, email, password, start_time):
        self.zenpy_client = Zenpy(subdomain=subdomain, email=email, password=password)
        self.start_time = start_time

    def get_tickets_data(self):
        return self.__get_incremental_data(zendesk_object=self.zenpy_client.tickets)

    def get_ticket_metrics_data(self):
        logging.info('m=get_ticket_metrics_data, start_time={}'.format(self.start_time))
        return self.zenpy_client.tickets.metrics_incremental(start_time=self.start_time)

    def get_satisfaction_ratings_data(self):
        logging.info('m=get_satisfaction_ratings_data, init')
        return self.zenpy_client.satisfaction_ratings(sort_order='asc')

    def get_requests_data(self):
        return self.__get_search_data(zendesk_type='request')

    def get_groups_data(self):
        return self.__get_search_data(zendesk_type='group')

    def get_group_memberships_data(self):
        return self.zenpy_client.group_memberships()

    def get_users_data(self):
        return self.__get_incremental_data(zendesk_object=self.zenpy_client.users)

    def __get_search_data(self, zendesk_type):
        logging.info('m=__get_search_data, zendesk_type={}, start_time={}'.format(zendesk_type, self.start_time))
        return self.zenpy_client.search(updated_after=self.start_time, type=zendesk_type)

    def __get_incremental_data(self, zendesk_object):
        logging.info('m=__get_incremental_data, start_time={}'.format(self.start_time))
        incremental_data_result = zendesk_object.incremental(start_time=self.start_time)
        if not incremental_data_result:
            logging.warn('m=__get_incremental_data, message=no result')
            return None

        return incremental_data_result
