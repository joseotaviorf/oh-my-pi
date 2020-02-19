from enum import Enum


class ZendeskTableEnum(Enum):
    TICKETS = 'tickets'
    TICKET_FIELDS = 'ticket_fields'
    GROUPS = 'groups'
    USERS = 'users'
    GROUP_MEMBERSHIPS = 'group_memberships'
    TICKET_METRICS = 'ticket_metrics'
    CUSTOM_FIELDS = 'custom_fields'
    FACT_TICKETS = 'fact_tickets'
    DIM_TICKET = 'dim_ticket'
    DIM_ZENDESK_USER = 'dim_zendesk_user'
