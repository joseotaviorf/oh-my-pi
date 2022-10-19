SELECT
    CAST(CAST(id_house AS STRING)||'00'||CAST(order_version AS STRING) AS BIGINT) AS id_house_listing,
    id_house,
    id_region,
    order_version AS version,
    status_history_new AS status_history,
    REGEXP_REPLACE(reason, '\n', '') AS status_change_reason,
    COALESCE(
      -- get MAX ts per id_house_listings per day
      MAX(rev) OVER(
      PARTITION BY id_house, order_version, CAST(ts_status_changed_new AS DATE)
                    ) = rev,
    false) AS is_last_status_of_day,
    ts_first_publication,
    ts_status_changed_new AS ts_status_started,
    ts_status_changed_next AS ts_status_ended
FROM 
    datalake_ebdb_listing.house_status_version_order
