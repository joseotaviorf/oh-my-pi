WITH
  last_activity AS (
    SELECT
      id_trackable,
      action,
      ts_activity_created
    FROM
      datalake_workable_redshift_clean.activities
    WHERE
      action IN ('requisition-on-hold', 'requisition-cancelled') 
    QUALIFY
        ts_activity_created = MAX(ts_activity_created) OVER (PARTITION BY id_trackable, action)
  ),
  on_hold_step1 AS (
    SELECT
      id_trackable,
      ts_activity_created,
      action,
      LEAD(action) OVER (PARTITION BY id_trackable ORDER BY ts_activity_created) AS next_action,
      LEAD(ts_activity_created) OVER (PARTITION BY id_trackable ORDER BY ts_activity_created) AS next_ts_activity_created
    FROM
      datalake_workable_redshift_clean.activities
    WHERE
      action IN ('requisition-on-hold', 'requisition-resumed', 'requisition-cancelled')
  ),
  on_hold_final AS (
    SELECT
      id_trackable,
      SUM(DATEDIFF(COALESCE(next_ts_activity_created, CURRENT_DATE), ts_activity_created)) AS days_on_hold_1
    FROM
      on_hold_step1
    WHERE
      action = 'requisition-on-hold'
    GROUP BY
      id_trackable
  ),
  requisition_dates_step1 AS (
    SELECT
      r.id,
      CASE
        WHEN ecf.dt_new_opened IS NOT NULL
        AND ecf.dt_new_opened < r.ts_created THEN ecf.dt_new_opened
        ELSE DATE(r.ts_created)
      END AS dt_created,
      COALESCE(ecf.dt_new_opened, r.dt_opened) AS dt_opened,
      CASE
        WHEN r.dt_filled < dt_opened THEN dt_opened
        ELSE r.dt_filled
      END AS dt_filled,
      DATE(cancelled_activity.ts_activity_created) AS dt_cancelled,
      DATE(on_hold_activity.ts_activity_created) AS dt_last_on_hold,
      COALESCE(ecf.dt_closure_renegotiated, ecf.dt_closure_expected) AS dt_closing_old_sla,
      CASE
        WHEN ecf.dt_new_opened IS NOT NULL THEN TRUE
        ELSE FALSE
      END has_used_dt_new_open,
      COALESCE(ohf.days_on_hold_1, 0) AS days_on_hold,
      CASE
        WHEN dt_opened IS NOT NULL THEN DATEDIFF(COALESCE(dt_filled, dt_cancelled, CURRENT_DATE), dt_opened) - days_on_hold
        ELSE 0
      END AS days_open,
      DATEDIFF(COALESCE(r.dt_opened, dt_cancelled, CURRENT_DATE), dt_created) AS days_queue
    FROM
      datalake_workable_redshift_clean.requisitions AS r
    LEFT JOIN 
      datalake_workable.custom_fields AS ecf 
        ON r.id = ecf.id_resource
    LEFT JOIN 
      last_activity AS cancelled_activity 
        ON r.id = cancelled_activity.id_trackable
        AND cancelled_activity.action = 'requisition-cancelled'
    LEFT JOIN 
      last_activity AS on_hold_activity 
        ON r.id = on_hold_activity.id_trackable
        AND on_hold_activity.action = 'requisition-on-hold'
    LEFT JOIN 
      on_hold_final AS ohf 
        ON r.id = ohf.id_trackable 
    QUALIFY
        r.ts_updated = MAX(r.ts_updated) OVER (PARTITION BY r.code)
  )
SELECT
  id,
  days_on_hold,
  days_open,
  days_queue,
  has_used_dt_new_open,
  dt_created,
  dt_opened,
  dt_filled,
  dt_cancelled,
  dt_last_on_hold,
  dt_closing_old_sla,
  NOW() AS ts_load
FROM
  requisition_dates_step1