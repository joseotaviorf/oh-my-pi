SELECT
    uid AS id,
    token,
    CAST(satisfaction_level AS INT) AS satisfaction_level,
    points_improvement,
    comment,
    answered,
    TO_TIMESTAMP(submitted_at, 'dd/MM/yyyy HH:mm:ss') AS ts_submitted
FROM
    datalake_gsheets_raw.csat_faturas