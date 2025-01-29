SELECT
    id,
    card_id AS id_card,
    dashboard_id AS id_dashboard,
    sizeX AS size_x,
    sizeY AS size_y,
    row,
    col AS column,
    parameter_mappings,
    visualization_settings,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.report_dashboardcard
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
