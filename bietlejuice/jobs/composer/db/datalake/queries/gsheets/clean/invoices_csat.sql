SELECT
    uid AS id,
    token,
    CAST(satisfaction_level AS INT) AS satisfaction_level,
    points_improvement,
    comment,
    answered,
    DATE(submitted_at) AS dt_submitted
FROM
    datalake_gsheets_raw.csat_faturas