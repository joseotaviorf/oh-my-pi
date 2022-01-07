SELECT
    CAST(satisfaction_level AS INT) AS satisfaction_level,
    points_improvement,
    comment,
    TO_TIMESTAMP(timestamp, 'dd/MM/yyyy HH:mm:ss') AS ts_submitted
FROM
    datalake_gsheets_raw.csat_reembolso_pos_rescisao