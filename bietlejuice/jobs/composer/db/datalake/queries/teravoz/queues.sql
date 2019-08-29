select
    int(id) as id,
    smallint(number) as queue_number,
    description,
    smallint(logged_in) as agents_logged,
    smallint(available_agent) as available_agents_logged,
    smallint(callers) as queued_calls,
    current_timestamp as ts_load
from
    datalake_teravoz_raw.queues;