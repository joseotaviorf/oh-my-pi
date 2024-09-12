WITH base_detractor AS (
    -- base with all detractor queries from current year, its user, its first and last detractor occurrence
    SELECT
      id_superset_dashboard,
      id_superset_slice,
      slice_name,
      dashboard_name,
      executor_user AS executor_email,
      last_owner AS owner_email,
      MIN(ts_execution_start) AS first_det_execution,
      MAX(ts_execution_start) AS last_det_execution,
      COUNT(1) AS count_times
    FROM
      datalake_trino.trino_detractor_queries AS det
    WHERE
      executor_user IS NOT NULL
      AND id_superset_slice != 0
      AND DATE(ts_execution_start) >= DATE("{detractor_start_date}")
      AND (
        det.input_data_gb_threshold_active IS TRUE
        OR det.cpu_time_sec_threshold_active IS TRUE
        OR det.stages_threshold_active IS TRUE
        OR det.execution_time_sec_threshold_active IS TRUE
      )
    GROUP BY ALL
  ),
  full_base AS (
    SELECT
      det.id_superset_dashboard,
      det.id_superset_slice,
      det.slice_name,
      det.dashboard_name,
      det.executor_user AS executor_email,
      det.last_owner AS last_owner_email,
      we.week_start,
      COUNT(*) OVER (PARTITION BY det.id_superset_dashboard, det.id_superset_slice, det.executor_user, det.id_superset_slice, det.last_owner) AS detractor_runs,
      MAX(det.ts_execution_start) AS last_detractor_of_week
    FROM
      datalake_trino.trino_detractor_queries AS det
    LEFT JOIN
      dw_public.dim_date AS we
        ON we.`date` = DATE(det.ts_execution_start)
    WHERE
      det.last_owner IS NOT NULL
      AND det.id_superset_slice != 0
      AND DATE(det.ts_execution_start) >= DATE("{detractor_start_date}")
      AND (
        det.input_data_gb_threshold_active IS TRUE
        OR det.cpu_time_sec_threshold_active IS TRUE
        OR det.stages_threshold_active IS TRUE
        OR det.execution_time_sec_threshold_active IS TRUE
      )
    GROUP BY ALL
  ),
  base_superset AS (
    SELECT DISTINCT
      l.id_user,
      l.id_dashboard,
      l.id_slice,
      us.email,
      sl.last_owner,
      we.week_start,
      COUNT(*) AS superset_runs,
      MAX(l.ts_event) AS last_superset_run_of_week
    FROM
      datalake_superset_clean.logs AS l
    LEFT JOIN
      datalake_superset_clean.ab_user AS us
        ON us.id = l.id_user
    LEFT JOIN
      datalake_superset.slices AS sl
        ON sl.id = l.id_slice
    LEFT JOIN
      dw_public.dim_date we ON we.`date` = date(ts_event)
    WHERE
      action = "ChartDataRestApi.data"
      AND id_slice != 0
    GROUP BY ALL
  ),
  first_part AS (
    SELECT
      f.id_superset_dashboard,
      f.id_superset_slice,
      f.slice_name,
      f.dashboard_name,
      f.executor_email,
      f.last_owner_email,
      f.week_start,
      f.detractor_runs,
      f.last_detractor_of_week,
      sup.superset_runs,
      sup.last_superset_run_of_week,
      CASE
        WHEN sup.last_superset_run_of_week IS NULL THEN "Detractor" -- there is no successful run in metabase that matches
        WHEN ABS(DATEDIFF(MINUTE, sup.last_superset_run_of_week, f.last_detractor_of_week)) < 3 THEN "Detractor" -- last metabase run is probably the last detractor found
        WHEN DATEDIFF(SECOND, sup.last_superset_run_of_week, f.last_detractor_of_week) < 0 THEN "Non Detractor" -- last metabase run is greater than last detractor, so some successful run happened
        WHEN DATEDIFF(SECOND, sup.last_superset_run_of_week, f.last_detractor_of_week) > 0 THEN "Detractor" -- last metabase run is lower than last detractor, the detractor run failed in metabase
        ELSE "FALLBACK NOT CONFIGURED"
      END AS is_detractor -- no scenario passed here
    FROM
        full_base AS f
    LEFT JOIN
        base_superset AS sup
          ON sup.email = f.executor_email
          AND sup.id_slice = f.id_superset_slice
          AND sup.week_start = f.week_start
          AND sup.last_owner = f.last_owner_email
    WHERE
      sup.superset_runs IS NOT NULL
    -- order by f.id_card, f.user_id, f.week_start, f.detractor_runs desc
  ),
  second_part AS (
    SELECT
      sup.*,
      users_slices.executor_email,
      users_slices.dashboard_name,
      users_slices.slice_name
    FROM
      base_superset AS sup
    JOIN
      base_detractor AS users_slices
        ON users_slices.id_superset_slice = sup.id_slice
        AND users_slices.executor_email = sup.email
    JOIN
      dw_public.dim_date AS week_st
        ON week_st.`date` = DATE(users_slices.first_det_execution)
    JOIN
      dw_public.dim_date AS week_end
        ON week_end.`date` = DATE(users_slices.last_det_execution)
    LEFT JOIN
      first_part AS fp
        ON fp.id_superset_slice = sup.id_slice
        AND fp.executor_email = sup.email
        AND fp.week_start = sup.week_start
    WHERE
      sup.week_start BETWEEN week_st.week_start AND week_end.week_start
      AND fp.executor_email IS NULL
  ),
  complete_base as (
    SELECT
      fp.id_superset_dashboard,
      fp.id_superset_slice,
      fp.dashboard_name,
      fp.slice_name,
      fp.executor_email,
      fp.last_owner_email,
      fp.week_start,
      fp.detractor_runs,
      fp.last_detractor_of_week,
      fp.superset_runs,
      fp.last_superset_run_of_week,
      fp.is_detractor
    FROM
      first_part AS fp
    UNION ALL
    SELECT
      sp.id_dashboard AS id_superset_dashboard,
      sp.id_slice AS id_superset_slice,
      sp.dashboard_name,
      sp.slice_name,
      sp.email AS executor_email,
      sp.last_owner AS last_owner_email,
      sp.week_start,
      0 AS detractor_runs,
      NULL AS last_detractor_of_week,
      sp.superset_runs,
      sp.last_superset_run_of_week,
      "Non Detractor" AS is_detractor
    FROM
      second_part AS sp
  )
  SELECT
    base.id_superset_dashboard,
    base.id_superset_slice,
    base.dashboard_name,
    base.slice_name,
    base.executor_email,
    base.last_owner_email,
    base.week_start,
    base.detractor_runs,
    base.is_detractor,
    base.superset_runs,
    COUNT(DISTINCT counts.week_start) AS count_detractors,
    base.last_detractor_of_week AS ts_last_detractor_of_week,
    base.last_superset_run_of_week AS ts_last_superset_run_of_week
  FROM
    complete_base AS base
  LEFT JOIN
    complete_base AS counts
      ON counts.id_superset_slice = base.id_superset_slice
      AND counts.executor_email = base.executor_email
      AND counts.is_detractor = "Detractor"
      AND counts.week_start BETWEEN ADD_MONTHS(DATE("{load_start_date}"), -3) AND base.week_start
  GROUP BY ALL
