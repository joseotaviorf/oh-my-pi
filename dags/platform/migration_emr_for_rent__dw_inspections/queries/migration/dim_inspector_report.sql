SELECT
    COALESCE(id_report, -1) AS sk_report,
    inspection_type,
    room_type,
    item_group_type,
    item_type,
    issue_type,
    media_type,
    item_group_status,
    item_status,
    item_comment,
    issue_comment,
    room_name,
    item_group_name,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_inspections.inspector_reports
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
