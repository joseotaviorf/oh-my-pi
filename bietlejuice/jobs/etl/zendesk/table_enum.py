from enum import Enum


class ZendeskTableEnum(Enum):
    TICKETS = 'tickets'
    TICKET_FIELDS = 'ticket_fields'
    GROUPS = 'groups'
    USERS = 'users'
    GROUP_MEMBERSHIPS = 'group_memberships'
    TICKET_METRICS = 'ticket_metrics'
