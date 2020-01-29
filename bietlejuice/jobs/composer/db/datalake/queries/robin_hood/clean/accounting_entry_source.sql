select
    id,
    code,
    abbr,
    description,
    timestamp(created_at) as ts_created,
    boolean(active) as is_active
from
    datalake_robin_hood_raw.accounting_entry_source