SELECT
    city_group,
    lead,
    mkt_channel,
    CAST(fl AS DECIMAL(12,4)) AS fl,
    CAST(op AS DECIMAL(12,4)) AS op,
    CAST(opp AS DECIMAL(12,4)) AS opp,
    CAST(q AS DECIMAL(12,4)) AS q,    
    TO_DATE(date, 'M/d/yyyy') AS dt_created,
    TO_DATE(week_start, 'M/d/yyyy') AS dt_week_start,
    CAST(year AS INT) AS year,
    CAST(halfyear AS INT) AS semester,
    CAST(quarter AS INT) AS quarter,
    CAST(month AS INT) AS month
FROM
    datalake_gsheets_raw.forecast_diario_supply