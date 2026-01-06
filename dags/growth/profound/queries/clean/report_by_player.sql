SELECT
    asset_name AS player,
    CAST(executions AS INT) AS executions,
    CAST(mentions_count AS INT) AS mentions_count,
    CAST(visibility_score AS DOUBLE) AS visibility_score,
    CAST(share_of_voice AS DOUBLE) AS share_of_voice,
    date AS dt_created,
    YEAR(date) AS year,
    MONTH(date) AS month,
    DAY(date) AS day
FROM
    datalake_profound_raw.report_by_player
WHERE
    date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')