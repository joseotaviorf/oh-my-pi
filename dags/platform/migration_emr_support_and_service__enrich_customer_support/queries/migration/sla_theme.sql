WITH exploded_theme_sla AS (
    SELECT
        journey_step,
        contact_theme_tag AS theme,
        sla_in_days AS sla,
        EXPLODE(SEQUENCE(dt_start, COALESCE(dt_end, DATE("{load_end_date}")))) AS dt_reference
    FROM
        datalake_gsheets_clean.taxonomy_sla
    WHERE
        dt_target_invalidated IS NULL
),
min_sla_per_day AS (
    SELECT
        dt_reference,
        journey_step,
        theme,
        MIN(sla) AS sla
    FROM
        exploded_theme_sla
    GROUP BY ALL
)
SELECT
    journey_step,
    theme,
    sla,
    MIN(dt_reference) AS dt_start,
    MAX(dt_reference) AS dt_end
FROM
    min_sla_per_day
GROUP BY ALL
