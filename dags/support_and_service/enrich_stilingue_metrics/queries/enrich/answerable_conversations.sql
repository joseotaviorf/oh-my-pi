WITH answerable AS (
    SELECT
        SUM(
            CAST(
                CASE
                    WHEN is_answerable IS TRUE THEN TRUE
                    ELSE FALSE
                END
            AS SMALLINT)
        ) AS total_answerable,
        SUM(
            CAST(
                CASE
                    WHEN is_handled IS TRUE THEN TRUE
                    ELSE FALSE
                END
            AS SMALLINT)
        ) AS total_handled,
        dt_week
    FROM
        datalake_stilingue.service_interactions
    GROUP BY 3
)
SELECT
    ad.quarter,
    ad.calendar_week,
    total_answerable,
    total_handled,
    dt_week
FROM
    answerable a
LEFT JOIN
    datalake_quintoandar.aux_date ad
        ON ad.date = a.dt_week