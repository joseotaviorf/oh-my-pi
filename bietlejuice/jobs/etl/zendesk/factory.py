from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.zendesk import ZendeskTableEnum, ZendeskTickets, ZendeskTicketFields, ZendeskGroups, ZendeskUsers, ZendeskGroupMemberships,\
    ZendeskTicketMetrics, ZendeskFactTickets, ZendeskDimTicket, ZendeskDimUser, ZendeskCustomFields, ZendeskFactTicketTags, ZendeskFactTicketContactTypes

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
            ZendeskTableEnum.USERS: ZendeskUsers,
            ZendeskTableEnum.GROUP_MEMBERSHIPS: ZendeskGroupMemberships,
            ZendeskTableEnum.TICKET_METRICS: ZendeskTicketMetrics,
            ZendeskTableEnum.CUSTOM_FIELDS: ZendeskCustomFields,
            ZendeskTableEnum.FACT_TICKETS: ZendeskFactTickets,
            ZendeskTableEnum.FACT_TICKET_CONTACT_TYPES: ZendeskFactTicketContactTypes,
            ZendeskTableEnum.FACT_TICKET_TAGS: ZendeskFactTicketTags,
            ZendeskTableEnum.DIM_TICKET: ZendeskDimTicket,
            ZendeskTableEnum.DIM_ZENDESK_USER: ZendeskDimUser,
        }.get(entity)
