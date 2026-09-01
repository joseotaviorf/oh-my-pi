WITH houses AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        MIN(ts_updated) OVER (PARTITION BY id_house) AS ts_first_publication,
        MAX(ts_updated) OVER (PARTITION BY 1) AS ts_last_extraction,
        ts_updated,
        LEAD(ts_updated) OVER(PARTITION BY id_house ORDER BY ts_updated) AS dt_next_updated
    FROM
        datalake_sale_crawlers_listings.em_casa_region_mapping
),
-- EMR Spark 3.5 plans a BroadcastNestedLoopJoin for `ad.date >= ts_updated AND ad.date <
-- COALESCE(...)` (no extractable hash key). Replace the range join against the aux_date
-- calendar with a per-house EXPLODE(SEQUENCE(...)) that generates the same weekly
-- (week_start) boundaries directly, matching aux_date.week_start semantics: the first
-- Monday on/after ts_updated, stepping by 7 days up to (but excluding) the next update.
houses_with_week_range AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        ts_updated,
        ts_last_extraction,
        CASE
            WHEN CAST(DATE_TRUNC('week', ts_updated) AS DATE) = ts_updated THEN ts_updated
            ELSE DATE_ADD(CAST(DATE_TRUNC('week', ts_updated) AS DATE), 7)
        END AS first_week_start,
        COALESCE(dt_next_updated, ts_last_extraction + 1) AS range_end_exclusive
    FROM
        houses
),
status_changes_raw AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        ts_last_extraction,
        CASE
            WHEN ts_updated = week_start THEN 'Publicado'
            ELSE 'Despublicado'
        END AS status_history,
        week_start AS ts_started_date
    FROM
        houses_with_week_range
    LATERAL VIEW EXPLODE(
        CASE
            WHEN first_week_start <= range_end_exclusive - 1
                THEN SEQUENCE(first_week_start, range_end_exclusive - 1, INTERVAL 7 DAY)
            ELSE CAST(ARRAY() AS ARRAY<DATE>)
        END
    ) exploded_weeks AS week_start
),
status_changes_flagged AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        status_history,
        ts_last_extraction,
        ts_started_date,
        LAG(status_history) OVER(PARTITION BY id_house ORDER BY ts_started_date) IS DISTINCT FROM status_history AS is_status_change
    FROM
        status_changes_raw
),
status_changes_aux AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        status_history,
        ts_last_extraction,
        ts_started_date
    FROM
        status_changes_flagged
    WHERE
        is_status_change
),
status_changes AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        status_history,
        ts_last_extraction,
        ts_started_date,
        DATE_SUB(LEAD(ts_started_date) OVER(PARTITION BY id_house ORDER BY ts_started_date), 7) AS ts_ended_date
    FROM
        status_changes_aux
)
SELECT
    id_house,
    id_house_platform,
    id_neighborhood,
    neighborhood,
    status_history,
    ts_ended_date IS NULL AS is_last_status,
    CASE
--      The DATEDIFF DIV 7 was used to emulate the old function DATE_DIFF and cast the number of days into the number of weeks.
        WHEN status_history = 'Publicado'
            THEN IF(
                DATEDIFF(COALESCE(ts_ended_date, ts_last_extraction), ts_started_date) DIV 7 = 0,
                1,
                DATEDIFF(COALESCE(ts_ended_date, ts_last_extraction), ts_started_date) DIV 7
            )
        ELSE NULL
    END AS weeks_published,
    CASE
        WHEN status_history = 'Despublicado'
            THEN IF(
                DATEDIFF(COALESCE(ts_ended_date, ts_last_extraction), ts_started_date) DIV 7 = 0,
                1,
                DATEDIFF(COALESCE(ts_ended_date, ts_last_extraction), ts_started_date) DIV 7
            )
        ELSE NULL
    END AS weeks_unpublished,
    ts_last_extraction,
    ts_started_date, -- This could have a better name, like dt_started or dt_status_started. However, this table comes from a migrated datamart
    ts_ended_date -- so renaming the columns is going to make the migration much harder for the dependent questions and looks.
FROM
    status_changes
