WITH assignment AS (
 SELECT DISTINCT
   a.id_period_of_service,
   a.id_assignment,
   a.assignment_number,
   a.id_person,
   a.id_business_unit,
   a.id_cost_center,
   a.id_job,
   a.id_cost_center,
   a.career_track,
   a.target_plr,
   COALESCE(
     a.band,
     LAG(a.band) OVER (
       PARTITION BY a.id_assignment
       ORDER BY
         a.ts_valid_from
     ),
     1
   ) AS band,
   a.action_code,
   a.dt_effective_start,
   a.assignment_status_type,
   a.dt_projected_start,
   IF(a.business_unit_name IN ('Benvi MX', 'Classifieds LATAM'),
      TIMESTAMP(dt_effective_start), a.ts_last_update) AS ts_valid_from
 FROM
   datalake_hr_system.assignments AS a
),
assignments_present AS (
 SELECT
   a.id_period_of_service,
   a.id_assignment,
   a.assignment_number,
   a.id_person,
   a.id_business_unit,
   a.id_cost_center,
   a.id_job,
   a.career_track,
   a.target_plr,
   SUM(
     CASE
       WHEN action_code = 'PROMOTION'
       OR band != LAG(band) OVER (
         PARTITION BY id_assignment
         ORDER BY
           a.ts_valid_from
       ) THEN 1
       ELSE 0
     END
   ) over (
     PARTITION BY id_assignment
     ORDER BY
       ts_valid_from
   ) AS qnt_promotions,
   a.dt_effective_start,
   a.dt_projected_start,
   a.assignment_status_type,
   a.ts_valid_from
 FROM
   assignment a
 WHERE
   DATE(a.ts_valid_from) <= DATE('{load_start_date}')
 QUALIFY
   DATE(a.ts_valid_from) = MAX(DATE(a.ts_valid_from)) OVER (PARTITION BY a.id_assignment)
),
assignments_future AS (
 SELECT
   a.id_period_of_service,
   a.id_assignment,
   a.assignment_number,
   a.id_person,
   a.id_business_unit,
   a.id_cost_center,
   a.id_job,
   a.career_track,
   a.target_plr,
   SUM(
     CASE
       WHEN action_code = 'PROMOTION'
       OR band != LAG(band) OVER (
         PARTITION BY id_assignment
         ORDER BY
           ts_valid_from
       ) THEN 1
       ELSE 0
     END
   ) over (
     PARTITION BY id_assignment
     ORDER BY
       ts_valid_from
   ) AS qnt_promotions,
   a.dt_effective_start,
   a.dt_projected_start,
   a.assignment_status_type,
   a.ts_valid_from
 FROM
   assignment a
 WHERE
   DATE(a.ts_valid_from) > DATE('{load_start_date}')
 QUALIFY
   ts_valid_from = MAX(ts_valid_from) OVER (PARTITION BY a.id_assignment)
),
managers_present AS (
 SELECT
   DISTINCT id_period_of_service,
   id_assignment,
   id_manager_assignment
 FROM
   datalake_hr_system.managers
 WHERE
   DATE(ts_valid_from) <= DATE('{load_start_date}')
   AND manager_type = 'LINE_MANAGER'
 QUALIFY
   ts_valid_from = MAX(ts_valid_from) OVER (PARTITION BY id_assignment)
),
managers_future AS (
 SELECT
   DISTINCT id_period_of_service,
   id_assignment,
   id_manager_assignment
 FROM
   datalake_hr_system.managers
 WHERE
   DATE(ts_valid_from) > DATE('{load_start_date}')
   AND manager_type = 'LINE_MANAGER'
 QUALIFY
   ts_valid_from = MAX(ts_valid_from) OVER (PARTITION BY id_assignment)
),
hr_system_workers AS (
 SELECT
   id_person,
   work_relationships,
   external_identifiers
 FROM
   datalake_hr_system_clean.workers
 WHERE
   dt_effective = REPLACE('{load_start_date}', '-', '')
),
external_identifiers_step1 AS (
 SELECT
   id_person,
   explode(external_identifiers) external_identifiers
 FROM
   hr_system_workers
),
external_identifiers AS (
 SELECT
   id_person
 FROM
   external_identifiers_step1
 WHERE
   external_identifiers ['ExternalIdentifierType'] = 'ID_ONDA1'
),
work_rel_step1 AS(
 SELECT
   id_person,
   explode(work_relationships) as work_relationships
 FROM
   hr_system_workers
),
work_rel AS (
 SELECT
   id_person,
   work_relationships ['PeriodOfServiceId'] AS id_period_service,
   work_relationships ['assignments'] AS assignments
 FROM
   work_rel_step1
),
assignments_step1 AS (
 SELECT
   id_person,
   id_period_service,
   explode(assignments) as assignments
 FROM
   work_rel
),
assignments AS (
 SELECT
   id_person,
   id_period_service,
   assignments ['AssignmentId'] AS id_assignment
 FROM
   assignments_step1
),
managers_direct_led AS (
 SELECT
   id_manager_assignment,
   count(*) AS qnt_directly_led
 FROM
   managers_present
 GROUP BY
   id_manager_assignment
),
cte_enrich_disability AS (
  SELECT
    sk_disability,
    id_person,
    has_self_declared_disability
  FROM datalake_hr_system.disability
  QUALIFY
    ts_last_updated = MAX(ts_last_updated) over (PARTITION BY id_person)
    OR ts_last_updated is null
)


SELECT
 wr.id_period_of_service AS sk_assignment,
 wr.id_person AS sk_employee,
 COALESCE(da.sk_demographic_information, '-1') AS sk_demographic_information,
 COALESCE(ap.id_cost_center, af.id_cost_center, '-1') AS sk_cost_center,
 COALESCE(ap.id_business_unit, af.id_business_unit, '-1') AS sk_business_unit,
 coalesce(ap.id_job, af.id_job, '-1') AS sk_job,
 CASE
   WHEN COALESCE(
     ap_manager.id_assignment,
     af_manager.id_assignment
   ) IS NULL
     THEN '-1'
   ELSE COALESCE(ap_manager.id_person, af_manager.id_person, '-1')
 END AS sk_manager,
 CASE
   WHEN COALESCE(
     ap_manager.id_assignment,
     af_manager.id_assignment
   ) IS NULL
     THEN '-1'
   ELSE COALESCE(
     ap_manager.id_period_of_service,
     af_manager.id_period_of_service,
     '-1'
   )
 END AS sk_manager_assignment,
 COALESCE(d.sk_disability, '-1') AS sk_disability,
 sm.sk_last_increase_date,
 sm.sk_first_promotion_date,
 wr.worker_type,
 COALESCE(ap.assignment_number, af.assignment_number) AS assignment_number,
 COALESCE(sm.currency_code, -1) AS salary_currency,
 CASE
   WHEN wr.dt_start = MAX(wr.dt_start) OVER (PARTITION BY wr.id_person)
     THEN TRUE
   ELSE FALSE
 END AS is_last_work_relationship,
 CASE
   WHEN ap.assignment_status_type = 'ACTIVE'
     THEN TRUE
   ELSE FALSE
 END AS is_active,
 CASE
   WHEN wr.worker_type = 'P'
     THEN TRUE
   ELSE FALSE
 END AS is_pending_worker,
 CASE
   WHEN ap.career_track = 'L'
   OR mdl.qnt_directly_led > 0
     THEN TRUE
   ELSE FALSE
 END AS is_manager,
 COALESCE(d.has_self_declared_disability, FALSE) AS has_self_declared_disability,
 CASE
   WHEN wr.worker_type = 'P'
     THEN 0
   ELSE INT(
     months_between(
       coalesce(wr.dt_termination, DATE('{load_start_date}')),
       wr.dt_start
     )
   )
 END AS assignment_age_months,
 COALESCE(mdl.qnt_directly_led, 0) AS qnt_directly_led,
 COALESCE(ap.qnt_promotions, 0) AS qnt_promotions,
 COALESCE(sm.current_salary_amount, -1) AS salary,
 COALESCE(ap.target_plr, 0) AS target_plr,
 COALESCE(sm.salary_reference, 0) AS salary_reference,
 COALESCE(sm.qnt_movimentations, 0) AS qnt_movimentations,
 COALESCE(sm.average_time_between_movimentations, 0) AS average_time_between_movimentations,
 COALESCE(sm.last_salary_increase, 0) AS last_increase,
 COALESCE(sm.pct_last_salary_increase, 0) AS pct_last_increase,
 COALESCE(sm.first_salary_amount, 0) AS first_salary,
 COALESCE(sm.previous_salary_amount, 0) AS last_salary,
 COALESCE(sm.range_salary_movement, 0) AS range_salary_movement,
 COALESCE(sm.first_promotion_salary, 0) AS first_promotion_salary,
 COALESCE(sm.nominal_increase_first_promotion, 0) AS nominal_increase_first_promotion,
 COALESCE(sm.pct_increase_first_promotion, 0) AS pct_increase_first_promotion,
 DATEDIFF(MONTH, CASE WHEN wr.worker_type = 'P' THEN COALESCE(ap.dt_projected_start, af.dt_projected_start) ELSE wr.dt_start END, sm.dt_first_promotion) AS months_to_first_promotion,
 CASE
   WHEN wr.worker_type = 'P'
     THEN
       COALESCE(ap.dt_projected_start, af.dt_projected_start)
   ELSE wr.dt_start
 END AS dt_start_work_relationship,
 wr.dt_termination AS dt_termination_work_relationship,
 NOW() AS ts_load
FROM
 datalake_hr_system.work_relationships AS wr
LEFT JOIN
 assignments_present AS ap
   ON wr.id_period_of_service = ap.id_period_of_service
LEFT JOIN
 assignments_future AS af
   ON wr.id_period_of_service = af.id_period_of_service
LEFT JOIN
 managers_present AS mp
   ON wr.id_period_of_service = mp.id_period_of_service
LEFT JOIN
 managers_future AS mf
   ON wr.id_period_of_service = mf.id_period_of_service
LEFT JOIN
 assignments_present AS ap_manager
   ON COALESCE(
         mp.id_manager_assignment,
         mf.id_manager_assignment
       ) = ap_manager.id_assignment
LEFT JOIN
 assignments_future AS af_manager
   ON COALESCE(
         mp.id_manager_assignment,
         mf.id_manager_assignment
       ) = af_manager.id_assignment
LEFT JOIN
 managers_direct_led AS mdl
   ON ap.id_assignment = mdl.id_manager_assignment
LEFT JOIN
 datalake_hr_system.salary_metrics AS sm
   ON COALESCE(ap.id_assignment, af.id_assignment) = sm.id_assignment
LEFT JOIN
 datalake_hr_system.demographic_attributes AS da
   ON wr.id_person = da.id_person
     AND wr.legislation_code = da.legislation_code
LEFT JOIN
 cte_enrich_disability AS d
   ON wr.id_person = d.id_person
WHERE
 (
   wr.dt_start <= DATE('{load_start_date}')
   AND wr.worker_type IN ('E', 'C')
 )
 OR (
   COALESCE(ap.dt_projected_start, af.dt_projected_start) > DATE('{load_start_date}')
   AND wr.worker_type = 'P'
 )
