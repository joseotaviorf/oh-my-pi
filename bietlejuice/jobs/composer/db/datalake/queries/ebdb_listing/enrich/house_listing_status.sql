select
    cast(cast(id_house as string)||'00'||cast(order_version as string) as bigint) as id_house_listing,
    id_house,
    id_region,
    order_version as version,
    status_history_new as status_history,
    regexp_replace(reason, '\n', '') as status_change_reason,
    coalesce(
      -- get max ts per id_house_listings per day
      max(ts_status_changed_new) over(
	    partition by id_house, order_version, cast(ts_status_changed_new as date)
      ) = ts_status_changed_new,
    false) as is_last_status_of_day,
    ts_first_publication,
    ts_status_changed_new as ts_status_started,
    ts_status_changed_next as ts_status_ended
from datalake_ebdb_listing.house_status_version_order
