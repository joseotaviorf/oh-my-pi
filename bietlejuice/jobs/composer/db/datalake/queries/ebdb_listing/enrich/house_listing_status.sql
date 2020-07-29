select
    cast(cast(id_house as string)||'00'||cast(order_version as string) as bigint) as id_house_listing,
    id_region,
    status_history_new as status_history,
    regexp_replace(reason, '\n', '') as status_change_reason,
    ts_first_publication,
    ts_status_changed_new as ts_status_started,
    ts_status_changed_next as ts_status_ended
from datalake_ebdb_listing.house_status_version_order
