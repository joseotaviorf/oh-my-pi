SELECT
    quarter,
    year_month,
    line,
    dashboard_path,
    title as dashboard_title,
    ownership,
    CAST(views as INTEGER) as views,
    CAST(dt_last_view as TIMESTAMP) as ts_last_view,
    comment,
    ts_load
FROM
    datalake_gsheets_raw.documentation_campaign_metabase_dashboards
