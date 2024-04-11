SELECT 
    id,
    created_by_fk AS id_user_created,
    changed_by_fk AS id_user_changed,
    dashboard_title,
    position_json,
    css,
    "description",
    slug,
    json_metadata,
    published,
    uuid,
    certified_by,
    certification_details,
    is_managed_externally,
    external_url,
    created_on AS ts_created,
    changed_on AS ts_changed,
    year,
    month,
    day
FROM datalake_superset_raw.dashboards
WHERE MAKE_DATE(year, month, day) BETWEEN {load_start_date} AND {load_end_date}