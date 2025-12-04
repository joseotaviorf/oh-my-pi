WITH
-- Get the last valid work relationship per employee at each point in time
last_valid_assignments AS (
  SELECT
    fa.*,
    fa.dt_valid_from,
    fa.dt_valid_to,
    ROW_NUMBER() OVER (
      PARTITION BY fa.sk_employee, fa.dt_valid_from
      ORDER BY CASE WHEN fa.is_pending_worker = FALSE THEN 0 ELSE 1 END,
               fa.sk_work_relationship_started_date DESC
    ) = 1 AS is_last_valid_for_period
  FROM
    dw_employee_test.fact_assignments AS fa
  WHERE
    NOT fa.is_pending_worker
    AND fa.is_last_valid_work_relationship
),
-- Base fact table with all attributes filtered to last valid work relationship
fact_employees_base AS (
  SELECT
    sk_assignment,
    sk_employee,
    sk_demographic_information,
    sk_disability,
    sk_cost_center_version,
    sk_business_unit,
    sk_job_version,
    sk_manager,
    sk_manager_assignment,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    sk_last_salary_increase_date,
    sk_hierarchy_version,
    assignment_number,
    salary_currency_code,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    salary,
    last_salary_increase,
    pct_last_salary_increase,
    dt_valid_from,
    dt_valid_to
  FROM
    last_valid_assignments
  WHERE
    is_last_valid_for_period
),
-- Calculate hash of attributes that can change to detect versions
fact_employees_with_hash AS (
  SELECT
    sk_employee,
    sk_assignment,
    sk_demographic_information,
    sk_disability,
    sk_cost_center_version,
    sk_business_unit,
    sk_job_version,
    sk_manager,
    sk_manager_assignment,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    sk_last_salary_increase_date,
    sk_hierarchy_version,
    assignment_number,
    salary_currency_code,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    salary,
    last_salary_increase,
    pct_last_salary_increase,
    dt_valid_from,
    dt_valid_to,
    MD5(CONCAT_WS('|',
      CAST(sk_assignment AS STRING),
      CAST(sk_demographic_information AS STRING),
      CAST(sk_disability AS STRING),
      CAST(sk_cost_center_version AS STRING),
      CAST(sk_business_unit AS STRING),
      CAST(sk_job_version AS STRING),
      CAST(sk_manager AS STRING),
      CAST(sk_manager_assignment AS STRING),
      CAST(sk_hierarchy_version AS STRING),
      CAST(salary_currency_code AS STRING),
      CAST(salary AS STRING),
      CAST(is_active AS STRING),
      CAST(is_manager AS STRING),
      CAST(has_self_declared_disability AS STRING)
    )) AS attributes_hash
  FROM
    fact_employees_base
),
-- Group consecutive periods with identical attributes
fact_employees_groups AS (
  SELECT
    *,
    SUM(CASE 
      WHEN LAG(attributes_hash) OVER (
        PARTITION BY sk_employee
        ORDER BY dt_valid_from
      ) <> attributes_hash
        OR LAG(attributes_hash) OVER (
          PARTITION BY sk_employee
          ORDER BY dt_valid_from
        ) IS NULL
      THEN 1
      ELSE 0
    END) OVER (
      PARTITION BY sk_employee
      ORDER BY dt_valid_from
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS change_group
  FROM
    fact_employees_with_hash
),
-- Consolidate consecutive periods with identical attributes into single SCD Type 2 versions
consolidated_fact_employees AS (
  SELECT
    sk_employee,
    sk_assignment,
    sk_demographic_information,
    sk_disability,
    sk_cost_center_version,
    sk_business_unit,
    sk_job_version,
    sk_manager,
    sk_manager_assignment,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    sk_last_salary_increase_date,
    sk_hierarchy_version,
    assignment_number,
    salary_currency_code,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    salary,
    last_salary_increase,
    pct_last_salary_increase,
    MIN(dt_valid_from) AS dt_valid_from,
    MAX(COALESCE(dt_valid_to, DATE('9999-12-31'))) AS dt_valid_to
  FROM
    fact_employees_groups
  GROUP BY
    sk_employee,
    change_group,
    sk_assignment,
    sk_demographic_information,
    sk_disability,
    sk_cost_center_version,
    sk_business_unit,
    sk_job_version,
    sk_manager,
    sk_manager_assignment,
    sk_work_relationship_started_date,
    sk_work_relationship_ended_date,
    sk_last_salary_increase_date,
    sk_hierarchy_version,
    assignment_number,
    salary_currency_code,
    is_active,
    is_pending_worker,
    is_manager,
    has_self_declared_disability,
    assignment_age_months,
    qnt_directly_led,
    qnt_undirectly_led,
    salary,
    last_salary_increase,
    pct_last_salary_increase
)

SELECT
  MD5(CONCAT_WS('|', CAST(cfe.sk_employee AS STRING), CAST(cfe.dt_valid_from AS STRING))) AS sk_employee_version,
  cfe.sk_employee,
  cfe.sk_assignment,
  cfe.sk_demographic_information,
  cfe.sk_disability,
  cfe.sk_cost_center_version,
  cfe.sk_business_unit,
  cfe.sk_job_version,
  cfe.sk_manager,
  cfe.sk_manager_assignment,
  cfe.sk_work_relationship_started_date,
  cfe.sk_work_relationship_ended_date,
  cfe.sk_last_salary_increase_date,
  cfe.sk_hierarchy_version,
  cfe.assignment_number,
  cfe.salary_currency_code,
  cfe.is_active,
  cfe.is_pending_worker,
  cfe.is_manager,
  cfe.has_self_declared_disability,
  cfe.assignment_age_months,
  cfe.qnt_directly_led,
  cfe.qnt_undirectly_led,
  cfe.salary,
  cfe.last_salary_increase,
  cfe.pct_last_salary_increase,
  ROW_NUMBER() OVER (
    PARTITION BY cfe.sk_employee
    ORDER BY cfe.dt_valid_from
  ) AS version,
  cfe.dt_valid_from,
  LEAST(
    COALESCE(
      LEAD(cfe.dt_valid_from) OVER (
        PARTITION BY cfe.sk_employee
        ORDER BY cfe.dt_valid_from
      ) - INTERVAL '1 DAY',
      DATE('9999-12-31')
    ),
    COALESCE(cfe.dt_valid_to, DATE('9999-12-31'))
  ) AS dt_valid_to,
  (
    LEAD(cfe.dt_valid_from) OVER (
      PARTITION BY cfe.sk_employee
      ORDER BY cfe.dt_valid_from
    ) IS NULL
  ) AS is_current,
  NOW() AS ts_load
FROM
  consolidated_fact_employees AS cfe

