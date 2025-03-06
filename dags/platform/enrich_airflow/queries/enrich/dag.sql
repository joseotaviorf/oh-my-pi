-- datalake_astro_clean.dag acts essentially as a snapshot table
-- Therefore, we need to get the most recent snapshot
WITH latest_date_aux AS (
    SELECT
        MAX(MAKE_DATE(year, month, day)) AS dt_max
    FROM
        datalake_astro_clean.dag
),
astro_dags AS (
    -- Yes, we are using every column. This enrich is supposed to be a replica from clean,
    -- but joining with old Composer data
    SELECT d.*
    FROM
        datalake_astro_clean.dag AS d
    JOIN
        latest_date_aux AS lda
            ON MAKE_DATE(d.year, d.month, d.day) = lda.dt_max
)
SELECT
    COALESCE(ad.id_dag, cd.id_dag) AS id_dag,
    COALESCE(ad.id_pickle, cd.id_pickle) AS id_pickle,
    COALESCE(ad.id_root_dag, cd.id_root_dag) AS id_root_dag,
    CASE
        WHEN ad.id_dag IS NULL THEN 'Composer'
        ELSE 'Astro'
    END AS source_provider,
    COALESCE(ad.default_view, cd.default_view) AS default_view,
    ad.dag_display_name,
    COALESCE(ad.description, cd.description) AS description,
    ad.dataset_expression,
    COALESCE(ad.fileloc, cd.fileloc) AS fileloc,
    COALESCE(ad.last_pickled, cd.last_pickled) AS last_pickled,
    COALESCE(ad.owners, cd.owners) AS owners,
    COALESCE(ad.schedule_interval, cd.schedule_interval) AS schedule_interval,
    ad.timetable_description,
    ad.processor_subdir,
    COALESCE(ad.scheduler_lock, cd.scheduler_lock) AS scheduler_lock,
    ad.max_active_runs,
    ad.max_active_tasks,
    ad.max_consecutive_failed_dag_runs,
    COALESCE(ad.is_active, cd.is_active) AS is_active,
    COALESCE(ad.is_paused, cd.is_paused) AS is_paused,
    COALESCE(ad.is_subdag, cd.is_subdag) AS is_subdag,
    ad.has_import_errors,
    ad.has_task_concurrency_limits,
    COALESCE(ad.ts_last_expired, cd.ts_last_expired) AS ts_last_expired,
    COALESCE(ad.ts_last_parsed, cd.ts_last_scheduler_ran) AS ts_last_scheduler_ran,
    ad.ts_next_dagrun,
    ad.ts_next_dagrun_create_after,
    ad.ts_next_dagrun_data_interval_start,
    ad.ts_next_dagrun_data_interval_end
FROM
    astro_dags AS ad
FULL OUTER JOIN -- Keeps old Composer DAGs showing up
    datalake_composer_clean.dag AS cd
        ON ad.id_dag = cd.id_dag
