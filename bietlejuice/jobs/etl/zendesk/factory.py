from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum
from bietlejuice.jobs.dags.zendesk.tickets import ZendeskTickets
from bietlejuice.jobs.dags.zendesk.ticket_fields import ZendeskTicketFields
from bietlejuice.jobs.dags.zendesk.groups import ZendeskGroups

logger = QuintoAndarLogger('ZendeskFactory')


class ZendeskFactory(object):
    @staticmethod
    def factory(entity, s3_bucket, execution_date):
        if entity is None:
            raise ValueError('m=factory, class_={}, msg=entity cannot be None')
        class_ = ZendeskFactory.__dispatch_dict(entity)
        if not class_:
            raise RuntimeError('m=factory, entity={}, msg=class type for entity not found'.format(entity))
        return class_(
            s3_bucket=s3_bucket,
            execution_date=execution_date)

    @staticmethod
    def __dispatch_dict(entity):
        return {
            ZendeskTableEnum.TICKETS: ZendeskTickets,
            ZendeskTableEnum.TICKET_FIELDS: ZendeskTicketFields,
            ZendeskTableEnum.GROUPS: ZendeskGroups,
        }.get(entity)
