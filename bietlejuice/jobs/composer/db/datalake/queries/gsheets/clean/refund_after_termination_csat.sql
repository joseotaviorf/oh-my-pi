SELECT
    CAST(satisfaction_level AS INT) AS satisfaction_level,
    points_improvement,
    comment,
    CAST(timestamp AS TIMESTAMP) AS ts_submitted
FROM
    datalake_gsheets_raw.csat_reembolso_pos_rescisao