WITH
subordinates AS (
  SELECT
    mh.id_manager_period_of_service,
    SUM(IF(mh.is_direct_manager AND ed.assignment_status_type = 'ACTIVE', 1, 0)) AS qnt_directly_led,
    SUM(IF(NOT mh.is_direct_manager AND ed.assignment_status_type = 'ACTIVE', 1, 0)) AS qnt_undirectly_led
  FROM
    datalake_hr_system.management_hierarchy AS mh
  LEFT JOIN
    datalake_employment.employee_details AS ed
      ON ed.id_assignment = mh.id_assignment
  GROUP BY
    mh.id_manager_period_of_service
),
current_salaries AS (
    SELECT
        id_assignment,
        currency_code,
        salary_amount
    FROM (
        SELECT
            s.id_assignment,
            s.currency_code,
            s.salary_amount,
            ROW_NUMBER() OVER (PARTITION BY s.id_assignment ORDER BY s.dt_ended DESC) AS _rn
        FROM
            datalake_pin_compensation_clean.salary AS s
        WHERE
            s.dt_started <= DATE('{load_start_date}')
    )
    WHERE _rn = 1
),
valid_salary_adjustments AS (
    SELECT
        id_assignment,
        adjustment_amount,
        adjustment_percent,
        dt_started,
        last_salary_increase_type
    FROM (
        SELECT
            s.id_assignment,
            s.adjustment_amount,
            s.adjustment_percent,
            s.dt_started,
            art.action_reason AS last_salary_increase_type,
            ROW_NUMBER() OVER (PARTITION BY s.id_assignment ORDER BY s.dt_started DESC) AS _rn
        FROM
            datalake_pin_compensation_clean.salary AS s
        INNER JOIN
            datalake_pin_core_clean.action_base AS ab
                ON ab.id_action = s.id_action
                AND ab.dt_ended = DATE('4712-12-31')
        LEFT JOIN
            datalake_pin_core_clean.action_reason_translation AS art
                ON art.id_action_reason = s.id_action_reason
                AND art.language = 'PTB'
        WHERE
            s.dt_started <= DATE('{load_start_date}')
            AND ab.action_code IN ('CHANGE_SALARY', 'PROMOTION', 'GLB_TRANSFER')
            AND (
                (s.adjustment_amount IS NOT NULL AND s.adjustment_amount <> 0)
                OR (s.adjustment_percent IS NOT NULL AND s.adjustment_percent <> 0)
            )
            AND art.action_reason IN ('Mérito', 'Promoção', 'Recrutamento Interno')
    )
    WHERE _rn = 1
),
current_assignments AS (
    SELECT
        id_period_of_service,
        id_job,
        id_organization,
        id_business_unit,
        legislation_code,
        assignment_status_type,
        dt_projected_started,
        target_plr,
        career_track
    FROM (
        SELECT
            id_period_of_service,
            id_job,
            id_organization,
            id_business_unit,
            legislation_code,
            assignment_status_type,
            dt_projected_started,
            target_plr,
            career_track,
            ROW_NUMBER() OVER (PARTITION BY id_period_of_service ORDER BY dt_effective_ended ASC) AS _rn
        FROM
            datalake_pin_core_clean.all_assignments
        WHERE
            (
                (
                    dt_effective_started <= DATE('{load_start_date}')
                    AND assignment_type IN ('E', 'C')
                )
                OR (
                    dt_projected_started > DATE('{load_start_date}')
                    AND assignment_type = 'P'
                )
            )
            AND dt_effective_ended >= DATE('{load_start_date}')
    )
    WHERE _rn = 1
),
managers AS (
    SELECT
        id_manager_period_of_service,
        id_assignment,
        id_manager,
        has_active_manager
    FROM (
        SELECT
            ma.id_manager_period_of_service,
            ma.id_assignment,
            ma.id_manager,
            COALESCE(ed_manager.assignment_status_type = 'ACTIVE', FALSE) AS has_active_manager,
            ROW_NUMBER() OVER (PARTITION BY ma.id_assignment ORDER BY ma.dt_effective_started DESC) AS _rn
        FROM
            datalake_pin.managers_history AS ma
        LEFT JOIN
            datalake_employment.employee_details AS ed_manager
                ON ed_manager.id_period_of_service = ma.id_manager_period_of_service
        WHERE
            ma.dt_effective_started <= DATE('{load_start_date}')
    )
    WHERE _rn = 1
)
SELECT
  im.id_period_of_service AS sk_assignment,
  im.id_person AS sk_employee,
  COALESCE(da.sk_demographic_information, '-1') AS sk_demographic_information,
  COALESCE(d.sk_disability, '-1') AS sk_disability,
  COALESCE(a.id_organization, '-1') AS sk_cost_center,
  COALESCE(a.id_business_unit, '-1') AS sk_business_unit,
  COALESCE(a.id_job, '-1') AS sk_job,
  COALESCE(am.id_manager, '-1') AS sk_manager,
  COALESCE(am.id_manager_period_of_service, '-1') AS sk_manager_assignment,
  DATE_FORMAT(ps.dt_started, 'yyyyMMdd') AS sk_work_relationship_started_date,
  DATE_FORMAT(ps.dt_actual_termination, 'yyyyMMdd') AS sk_work_relationship_ended_date,
  COALESCE(DATE_FORMAT(sa.dt_started, 'yyyyMMdd'), '-1') AS sk_last_salary_increase_date,
  COALESCE(h.sk_hierarchy, '-1') AS sk_hierarchy,
  im.assignment_number,
  cs.currency_code AS salary_currency_code,
  sa.last_salary_increase_type,
  ROW_NUMBER() OVER (
    PARTITION BY im.id_person
    ORDER BY
      CASE WHEN ed.assignment_type = 'P' THEN 1 ELSE 0 END ASC,
      ps.dt_started DESC NULLS LAST,
      NULLIF(ps.dt_actual_termination, DATE('4712-12-31')) DESC NULLS FIRST
  ) = 1 AS is_last_valid_work_relationship,
  IF(ed.assignment_status_type = 'ACTIVE', TRUE, FALSE) AS is_active,
  IF(ed.assignment_type = 'P', TRUE, FALSE) AS is_pending_worker,
  CASE
    WHEN a.career_track = 'L'
      OR sub.qnt_directly_led > 0
    THEN TRUE
    ELSE FALSE
  END AS is_manager,
  am.has_active_manager,
  ps.dt_started AS dt_work_relationship_started,
  ps.dt_actual_termination AS dt_work_relationship_ended,
  sa.dt_started AS dt_last_salary_increase,
  CASE 
    WHEN ed.assignment_type = 'P' THEN 0
    ELSE FLOOR(MONTHS_BETWEEN(COALESCE(ps.dt_actual_termination, DATE('{load_start_date}')), ps.dt_started)) 
  END AS assignment_age_months,
  COALESCE(sub.qnt_directly_led, 0) AS qnt_directly_led,
  COALESCE(sub.qnt_undirectly_led, 0) AS qnt_undirectly_led,
  cs.salary_amount AS salary,
  COALESCE(sa.adjustment_amount, 0) AS last_salary_increase,
  COALESCE(sa.adjustment_percent, 0) AS pct_last_salary_increase,
  NOW() AS ts_load
FROM 
  datalake_people.identifier_mapping AS im
INNER JOIN 
  datalake_employment.employee_details AS ed
    ON ed.id_period_of_service = im.id_period_of_service
INNER JOIN 
  current_assignments AS a
    ON a.id_period_of_service = im.id_period_of_service
LEFT JOIN 
  datalake_pin_core_clean.periods_of_service AS ps
    ON ps.id_period_of_service = im.id_period_of_service
LEFT JOIN
  subordinates AS sub 
    ON sub.id_manager_period_of_service = im.id_period_of_service
LEFT JOIN
  current_salaries AS cs
    ON cs.id_assignment = im.id_assignment
LEFT JOIN
  valid_salary_adjustments AS sa
    ON sa.id_assignment = im.id_assignment
LEFT JOIN
  datalake_hr_system.disability AS d
    ON d.id_person = im.id_person
LEFT JOIN
  datalake_hr_system.demographic_attributes AS da
    ON da.id_person = im.id_person
    AND a.legislation_code = da.legislation_code
LEFT JOIN
  datalake_hr_system.hierarchy_ids AS h
    ON h.sk_assignment = im.id_period_of_service
LEFT JOIN 
  managers AS am 
    ON am.id_assignment = im.id_assignment