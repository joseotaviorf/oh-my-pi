SELECT
    CAST(Data AS DATE) AS dt_created,
    CAST(Clicks AS INT) AS target_clicks

FROM
    datalake_gsheets_raw.seo_target_clicks_2025
