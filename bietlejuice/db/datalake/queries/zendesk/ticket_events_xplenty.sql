select
    t.metadata,
    t.system,
    t.event_type,
    t.updater_id,
    t.created_at,
    t.child_events,
    t.id,
    t.ticket_id,
    t.timestamp,
    t.via
from datalake_raw.zendesk_ticket_events_xplenty t
__WHERE_CLAUSE__