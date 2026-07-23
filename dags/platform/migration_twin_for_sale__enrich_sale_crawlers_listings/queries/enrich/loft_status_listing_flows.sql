WITH houses AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        MIN(dt_updated) OVER (PARTITION BY id_house) AS ts_first_publication,
        MAX(dt_updated) OVER (PARTITION BY 1) AS ts_last_extraction,
        dt_updated,
        LEAD(dt_updated) OVER(PARTITION BY id_house ORDER BY dt_updated) AS dt_next_updated
    FROM
        datalake_crawlers_listings.loft_region_mapping AS llrm
),
status_changes_aux AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        CASE 
            WHEN dt_updated = dd.date THEN 'Publicado'
            ELSE 'Despublicado'
        END AS status_history,
        ts_last_extraction,
        dd.date AS ts_started_date
    FROM
        houses AS h
    JOIN
        dw_public.dim_date AS dd
            ON dd.date >= dt_updated
            AND (dd.date < COALESCE(dt_next_updated, ts_last_extraction + 1))
            AND dd.date = dd.week_start
    QUALIFY
        LAG(status_history) OVER(PARTITION BY id_house ORDER BY dd.date) IS DISTINCT FROM status_history 
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
