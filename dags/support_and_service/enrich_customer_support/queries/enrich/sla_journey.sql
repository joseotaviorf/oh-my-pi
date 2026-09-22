WITH exploded_journey_taxonomy AS (
    SELECT
        journey_step,
        sla_in_days AS sla,
        EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE("{load_end_date}")))) AS dt_reference
    FROM
        datalake_gsheets_clean.taxonomy_sla
    WHERE
        dt_target_invalidated IS NULL
),
min_sla_per_day AS (
    SELECT
        journey_step,
        MIN(sla) AS sla,
        dt_reference
    FROM
        exploded_journey_taxonomy
    GROUP BY 1,3
)
SELECT
    journey_step,
    sla,
    MIN(dt_reference) AS dt_start,
    MAX(dt_reference) AS dt_end
FROM
    min_sla_per_day
GROUP BY
    journey_step,
    sla
