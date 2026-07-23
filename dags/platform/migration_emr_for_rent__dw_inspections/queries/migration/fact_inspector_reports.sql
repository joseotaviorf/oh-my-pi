SELECT
    COALESCE(id_report, -1) AS sk_report,
    COALESCE(id_inspection, -1) AS sk_inspection,
    COALESCE(id_inspector, -1) AS sk_inspector,
    COALESCE(id_contract, -1) AS sk_contract,
    COALESCE(id_appointment, -1) AS sk_appointment,
    COALESCE(id_room, -1) AS sk_room,
    COALESCE(id_item, -1) AS sk_item,
    COALESCE(id_item_group, -1) AS sk_item_group,
    COALESCE(id_item_issue, -1) AS sk_item_issue,
    COALESCE(id_item_media, -1) AS sk_item_media,
    is_present_item,
    ts_synced,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_inspections.inspector_reports
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
