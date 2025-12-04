WITH
-- Base CTE: Get all historical assignment versions with their effective dates
assignment_versions AS (
  SELECT 
    aa.id_period_of_service, 
    aa.id_job,
    aa.id_organization,
    aa.id_business_unit,
    aa.legislation_code, 
    aa.assignment_status_type,
    aa.dt_effective_started,
    aa.dt_effective_ended,
    aa.assignment_type,
    aa.career_track,
    aa.id_assignment
  FROM 
    datalake_pin_core_clean.all_assignments AS aa
  WHERE
    aa.assignment_type IN ('E', 'C', 'P')
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY aa.id_period_of_service, aa.dt_effective_started
      ORDER BY aa.dt_effective_ended ASC
    ) = 1
),
-- Get manager information for each assignment period
managers_by_period AS (
  SELECT
    mh.id_assignment,
    mh.id_period_of_service,
    mh.id_manager_period_of_service,
    mh.id_manager,
    mh.dt_effective_started,
    mh.dt_effective_ended
  FROM
    datalake_pin.managers_history AS mh
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY mh.assignment_number, mh.dt_effective_started
      ORDER BY mh.dt_effective_started DESC
    ) = 1
),
-- Get salary information for each assignment period
salaries_by_period AS (
  SELECT 
    s.id_assignment,
    s.currency_code,
    s.salary_amount,
    s.adjustment_amount,
    s.adjustment_percent,
    s.dt_started,
    s.dt_ended
  FROM 
    datalake_pin_compensation_clean.salary AS s
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY s.id_assignment, s.dt_started
      ORDER BY s.dt_ended DESC
    ) = 1
),
-- Get subordinates count by period using dim_hierarchy (historical approach)
-- Leader direct is the highest non-null lx (closest to employee)
subordinates_by_period AS (
  SELECT
    im_manager.id_period_of_service AS id_manager_period_of_service,
    dh.dt_valid_from,
    dh.dt_valid_to,
    SUM(IF(
      -- Direct leader: manager is the highest non-null lx level (l9 > l8 > ... > l1)
      (CASE
        WHEN dh.assignment_number_l9 IS NOT NULL THEN dh.assignment_number_l9
        WHEN dh.assignment_number_l8 IS NOT NULL THEN dh.assignment_number_l8
        WHEN dh.assignment_number_l7 IS NOT NULL THEN dh.assignment_number_l7
        WHEN dh.assignment_number_l6 IS NOT NULL THEN dh.assignment_number_l6
        WHEN dh.assignment_number_l5 IS NOT NULL THEN dh.assignment_number_l5
        WHEN dh.assignment_number_l4 IS NOT NULL THEN dh.assignment_number_l4
        WHEN dh.assignment_number_l3 IS NOT NULL THEN dh.assignment_number_l3
        WHEN dh.assignment_number_l2 IS NOT NULL THEN dh.assignment_number_l2
        WHEN dh.assignment_number_l1 IS NOT NULL THEN dh.assignment_number_l1
        ELSE NULL
      END = im_manager.assignment_number)
      AND aa_sub.assignment_status_type = 'ACTIVE', 
      1, 
      0
    )) AS qnt_directly_led,
    SUM(IF(
      -- Indirect leader: manager is in hierarchy but not the highest non-null lx
      im_manager.assignment_number IN (
        dh.assignment_number_l1, dh.assignment_number_l2, dh.assignment_number_l3,
        dh.assignment_number_l4, dh.assignment_number_l5, dh.assignment_number_l6,
        dh.assignment_number_l7, dh.assignment_number_l8, dh.assignment_number_l9
      )
      AND im_manager.assignment_number <> CASE
        WHEN dh.assignment_number_l9 IS NOT NULL THEN dh.assignment_number_l9
        WHEN dh.assignment_number_l8 IS NOT NULL THEN dh.assignment_number_l8
        WHEN dh.assignment_number_l7 IS NOT NULL THEN dh.assignment_number_l7
        WHEN dh.assignment_number_l6 IS NOT NULL THEN dh.assignment_number_l6
        WHEN dh.assignment_number_l5 IS NOT NULL THEN dh.assignment_number_l5
        WHEN dh.assignment_number_l4 IS NOT NULL THEN dh.assignment_number_l4
        WHEN dh.assignment_number_l3 IS NOT NULL THEN dh.assignment_number_l3
        WHEN dh.assignment_number_l2 IS NOT NULL THEN dh.assignment_number_l2
        WHEN dh.assignment_number_l1 IS NOT NULL THEN dh.assignment_number_l1
        ELSE NULL
      END
      AND aa_sub.assignment_status_type = 'ACTIVE',
      1,
      0
    )) AS qnt_undirectly_led
  FROM
    dw_employee_test.dim_hierarchy AS dh
  INNER JOIN
    datalake_employee_registration.identifier_mapping AS im_subordinate
      ON im_subordinate.assignment_number = dh.assignment_number
  INNER JOIN
    datalake_employee_registration.identifier_mapping AS im_manager
      ON im_manager.assignment_number IN (
        dh.assignment_number_l1, dh.assignment_number_l2, dh.assignment_number_l3,
        dh.assignment_number_l4, dh.assignment_number_l5, dh.assignment_number_l6,
        dh.assignment_number_l7, dh.assignment_number_l8, dh.assignment_number_l9
      )
  LEFT JOIN
    datalake_pin_core_clean.all_assignments AS aa_sub
      ON aa_sub.id_period_of_service = im_subordinate.id_period_of_service
      AND dh.dt_valid_from >= aa_sub.dt_effective_started
      AND dh.dt_valid_from < COALESCE(aa_sub.dt_effective_ended, DATE('9999-12-31'))
  WHERE
    im_manager.assignment_number IS NOT NULL
  GROUP BY
    im_manager.id_period_of_service,
    dh.dt_valid_from,
    dh.dt_valid_to
),
-- Get disability information (latest per person)
disability AS (
  SELECT DISTINCT
    sk_disability,
    id_person,
    has_self_declared_disability
  FROM 
    datalake_hr_system.disability
  QUALIFY
    ts_last_updated = MAX(ts_last_updated) OVER (PARTITION BY id_person)
),
-- Get cost_center_code from all_organization_units for joining with dim_cost_center
cost_center_codes AS (
  SELECT
    id_organization,
    cost_center_code,
    dt_effective_started,
    dt_effective_ended
  FROM
    datalake_pin_core_clean.all_organization_units
  WHERE
    cost_center_code IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY id_organization, dt_effective_started
      ORDER BY dt_effective_ended DESC
    ) = 1
),
-- Base fact table with all attributes for each assignment version period
fact_assignments_base AS (
  SELECT
    im.id_period_of_service AS sk_assignment,
    im.id_person AS sk_employee,
    av.id_organization,
    av.id_business_unit,
    av.id_job,
    av.legislation_code,
    av.assignment_status_type,
    av.assignment_type,
    av.career_track,
    av.dt_effective_started,
    av.dt_effective_ended,
    ccc.cost_center_code,
    COALESCE(da.sk_demographic_information, '-1') AS sk_demographic_information,
    COALESCE(d.sk_disability, '-1') AS sk_disability,
    COALESCE(am.id_manager, '-1') AS sk_manager,
    COALESCE(am.id_manager_period_of_service, '-1') AS sk_manager_assignment,
    COALESCE(h.sk_hierarchy, '-1') AS sk_hierarchy,
    im.assignment_number,
    COALESCE(s.currency_code, 'BRL') AS salary_currency_code,
    COALESCE(s.salary_amount, 0) AS salary,
    COALESCE(s.adjustment_amount, 0) AS last_salary_increase,
    COALESCE(s.adjustment_percent, 0) AS pct_last_salary_increase,
    DATE_FORMAT(s.dt_started, 'yyyyMMdd') AS sk_last_salary_increase_date,
    DATE_FORMAT(ps.dt_started, 'yyyyMMdd') AS sk_work_relationship_started_date,
    DATE_FORMAT(ps.dt_actual_termination, 'yyyyMMdd') AS sk_work_relationship_ended_date,
    IF(av.assignment_status_type = 'ACTIVE', TRUE, FALSE) AS is_active,
    IF(av.assignment_type = 'P', TRUE, FALSE) AS is_pending_worker,
    CASE
      WHEN av.career_track = 'L'
        OR COALESCE(sub.qnt_directly_led, 0) > 0
      THEN TRUE
      ELSE FALSE
    END AS is_manager,
    COALESCE(d.has_self_declared_disability, FALSE) AS has_self_declared_disability,
    COALESCE(sub.qnt_directly_led, 0) AS qnt_directly_led,
    COALESCE(sub.qnt_undirectly_led, 0) AS qnt_undirectly_led,
    CASE 
      WHEN av.assignment_type = 'P' THEN 0
      ELSE FLOOR(MONTHS_BETWEEN(
        COALESCE(av.dt_effective_ended, DATE('{load_start_date}')), 
        av.dt_effective_started
      ))
    END AS assignment_age_months,
    ROW_NUMBER() OVER (
      PARTITION BY im.id_person
      ORDER BY CASE WHEN av.assignment_type <> 'P' THEN ps.dt_started ELSE NULL END DESC NULLS LAST
    ) = 1 AS is_last_valid_work_relationship
  FROM 
    assignment_versions AS av
  INNER JOIN
    datalake_employee_registration.identifier_mapping AS im
      ON im.id_period_of_service = av.id_period_of_service
  LEFT JOIN
    datalake_pin_core_clean.periods_of_service AS ps
      ON ps.id_period_of_service = av.id_period_of_service
  LEFT JOIN
    cost_center_codes AS ccc
      ON ccc.id_organization = av.id_organization
      AND av.dt_effective_started >= ccc.dt_effective_started
      AND av.dt_effective_started < COALESCE(ccc.dt_effective_ended, DATE('9999-12-31'))
  LEFT JOIN
    managers_by_period AS am
      ON am.id_assignment = av.id_assignment
      AND av.dt_effective_started >= am.dt_effective_started
      AND av.dt_effective_started < COALESCE(am.dt_effective_ended, DATE('9999-12-31'))
  LEFT JOIN
    salaries_by_period AS s
      ON s.id_assignment = av.id_assignment
      AND av.dt_effective_started >= s.dt_started
      AND av.dt_effective_started < COALESCE(s.dt_ended, DATE('9999-12-31'))
  LEFT JOIN
    disability AS d
      ON d.id_person = im.id_person
  LEFT JOIN
    datalake_hr_system.demographic_attributes AS da
      ON da.id_person = im.id_person
      AND av.legislation_code = da.legislation_code
  LEFT JOIN
    datalake_hr_system.hierarchy_ids AS h
      ON h.sk_assignment = av.id_period_of_service
  LEFT JOIN
    subordinates_by_period AS sub
      ON sub.id_manager_period_of_service = av.id_period_of_service
      AND av.dt_effective_started >= sub.dt_valid_from
      AND av.dt_effective_started < COALESCE(sub.dt_valid_to, DATE('9999-12-31'))
),
-- Calculate hash of attributes that can change to detect versions
fact_assignments_with_hash AS (
  SELECT
    sk_assignment,
    sk_employee,
    COALESCE(id_organization, '-1') AS sk_cost_center,
    COALESCE(id_business_unit, '-1') AS sk_business_unit,
    COALESCE(id_job, '-1') AS sk_job,
    cost_center_code,
    sk_demographic_information,
    sk_disability,
    sk_manager,
    sk_manager_assignment,
    sk_hierarchy,
    assignment_number,
    salary_currency_code,
    salary,
    last_salary_increase,
    pct_last_salary_increase,
    sk_last_salary_increase_date,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    is_last_valid_work_relationship,
    dt_effective_started,
    dt_effective_ended,
    MD5(CONCAT_WS('|',
      CAST(COALESCE(id_organization, '-1') AS STRING),
      CAST(COALESCE(id_business_unit, '-1') AS STRING),
      CAST(COALESCE(id_job, '-1') AS STRING),
      CAST(sk_manager AS STRING),
      CAST(sk_manager_assignment AS STRING),
      CAST(sk_hierarchy AS STRING),
      CAST(salary_currency_code AS STRING),
      CAST(salary AS STRING),
      CAST(is_active AS STRING),
      CAST(is_manager AS STRING),
      CAST(has_self_declared_disability AS STRING)
    )) AS attributes_hash
  FROM
    fact_assignments_base
),
-- Group consecutive periods with identical attributes
fact_assignments_groups AS (
  SELECT
    *,
    SUM(CASE 
      WHEN LAG(attributes_hash) OVER (
        PARTITION BY sk_assignment
        ORDER BY dt_effective_started
      ) <> attributes_hash
        OR LAG(attributes_hash) OVER (
          PARTITION BY sk_assignment
          ORDER BY dt_effective_started
        ) IS NULL
      THEN 1
      ELSE 0
    END) OVER (
      PARTITION BY sk_assignment
      ORDER BY dt_effective_started
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS change_group
  FROM
    fact_assignments_with_hash
),
-- Consolidate consecutive periods with identical attributes into single SCD Type 2 versions
consolidated_fact_assignments AS (
  SELECT
    sk_assignment,
    sk_employee,
    sk_cost_center,
    sk_business_unit,
    sk_job,
    cost_center_code,
    sk_demographic_information,
    sk_disability,
    sk_manager,
    sk_manager_assignment,
    sk_hierarchy,
    assignment_number,
    salary_currency_code,
    salary,
    last_salary_increase,
    pct_last_salary_increase,
    sk_last_salary_increase_date,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    is_last_valid_work_relationship,
    MIN(dt_effective_started) AS dt_valid_from,
    MAX(COALESCE(dt_effective_ended, DATE('9999-12-31'))) AS dt_valid_to
  FROM
    fact_assignments_groups
  GROUP BY
    sk_assignment,
    change_group,
    sk_employee,
    sk_cost_center,
    sk_business_unit,
    sk_job,
    cost_center_code,
    sk_demographic_information,
    sk_disability,
    sk_manager,
    sk_manager_assignment,
    sk_hierarchy,
    assignment_number,
    salary_currency_code,
    salary,
    last_salary_increase,
    pct_last_salary_increase,
    sk_last_salary_increase_date,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    is_last_valid_work_relationship
),
-- Add business keys for joining with dimension tables
fact_assignments_with_keys AS (
  SELECT
    cfa.*,
    CAST(CASE WHEN cfa.sk_job = '-1' THEN NULL ELSE cfa.sk_job END AS BIGINT) AS id_job
  FROM
    consolidated_fact_assignments AS cfa
)

SELECT
  MD5(CONCAT_WS('|', CAST(cfa.sk_assignment AS STRING), CAST(cfa.dt_valid_from AS STRING))) AS sk_assignment_version,
  cfa.sk_assignment,
  cfa.sk_employee,
  cfa.sk_demographic_information,
  cfa.sk_disability,
  COALESCE(dcc.sk_cost_center_version, '-1') AS sk_cost_center_version,
  cfa.sk_business_unit,
  COALESCE(dj.sk_job_version, '-1') AS sk_job_version,
  cfa.sk_manager,
  cfa.sk_manager_assignment,
  cfa.sk_work_relationship_started_date,
  cfa.sk_work_relationship_ended_date,
  cfa.sk_last_salary_increase_date,
  COALESCE(dh.sk_hierarchy_version, '-1') AS sk_hierarchy_version,
  cfa.assignment_number,
  cfa.salary_currency_code,
  cfa.is_last_valid_work_relationship,
  cfa.is_active,
  cfa.is_pending_worker,
  cfa.is_manager,
  cfa.has_self_declared_disability,
  cfa.assignment_age_months,
  cfa.qnt_directly_led,
  cfa.qnt_undirectly_led,
  cfa.salary,
  cfa.last_salary_increase,
  cfa.pct_last_salary_increase,
  ROW_NUMBER() OVER (
    PARTITION BY cfa.sk_assignment
    ORDER BY cfa.dt_valid_from
  ) AS version,
  cfa.dt_valid_from,
  LEAST(
    COALESCE(
      LEAD(cfa.dt_valid_from) OVER (
        PARTITION BY cfa.sk_assignment
        ORDER BY cfa.dt_valid_from
      ) - INTERVAL '1 DAY',
      DATE('9999-12-31')
    ),
    COALESCE(cfa.dt_valid_to, DATE('9999-12-31'))
  ) AS dt_valid_to,
  (
    LEAD(cfa.dt_valid_from) OVER (
      PARTITION BY cfa.sk_assignment
      ORDER BY cfa.dt_valid_from
    ) IS NULL
  ) AS is_current,
  NOW() AS ts_load
FROM
  fact_assignments_with_keys AS cfa
LEFT JOIN
  dw_employee_test.dim_cost_center AS dcc
    ON cfa.cost_center_code = dcc.cost_center_code
    AND cfa.dt_valid_from >= dcc.dt_valid_from
    AND cfa.dt_valid_from < dcc.dt_valid_to
LEFT JOIN
  dw_employee_test.dim_job AS dj
    ON cfa.id_job = dj.id_job
    AND cfa.dt_valid_from >= dj.dt_valid_from
    AND cfa.dt_valid_from < dj.dt_valid_to
LEFT JOIN
  dw_employee_test.dim_hierarchy AS dh
    ON cfa.assignment_number = dh.assignment_number
    AND cfa.dt_valid_from >= dh.dt_valid_from
    AND cfa.dt_valid_from < dh.dt_valid_to
