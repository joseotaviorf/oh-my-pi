SELECT
    BIGINT(STRING(id_house)||'00'||STRING(order_version)) AS id_sale_listing,
    id_house,
    id_region,
    status_history_new AS status_history,
    REGEXP_REPLACE(reason, '\n', '') AS status_change_reason,
    COALESCE(
      -- get max ts per id_house_listings per day
      MAX(ts_status_changed_new) OVER(
        PARTITION BY id_house, order_version, CAST(ts_status_changed_new AS DATE)
      ) = ts_status_changed_new,
    FALSE) AS is_last_status,
    ts_first_publication,
    ts_status_changed_new AS ts_status_started,
    ts_status_changed_next AS ts_status_ended
FROM 
    datalake_sale_listings.sale_status_version_order
