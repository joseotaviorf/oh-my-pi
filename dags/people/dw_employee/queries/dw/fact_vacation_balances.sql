WITH 
vacation AS (
  SELECT
    id_period_of_service,
    period,
    SUM(days_duration) AS days_vacation_absence,
    SUM(vacation_cash_out_request) AS days_vacation_cash_out
  FROM
    datalake_pin_absence_clean.person_entry
  WHERE
    approval_status_code <> 'DENIED'
    AND absence_status_code = 'SUBMITTED'
    AND period IS NOT NULL
  GROUP BY
    id_period_of_service,
    period
)

SELECT
  aei.id_assignment_extra_info AS sk_vacation_balance,
  ei.id_person AS sk_employee,
  ei.id_period_of_service AS sk_assignment,
  DATE_FORMAT(aei.dt_period_started, 'yyyyMMdd') AS sk_accrual_started_date,
  DATE_FORMAT(aei.dt_period_ended, 'yyyyMMdd') AS sk_accrual_ended_date,
  DATE_FORMAT(aei.dt_period_ended + 365, 'yyyyMMdd') AS sk_accrual_expiration_date,
  MD5(aei.type_or_status) AS sk_vacation_status,
  aei.days_vacation_acquired AS days_accrued,
  COALESCE(v.days_vacation_absence, 0) AS days_vacation_taken_absence,
  COALESCE(v.days_vacation_cash_out, 0) AS days_vacation_taken_cash_out,
  COALESCE(v.days_vacation_absence + v.days_vacation_cash_out, 0) AS total_days_taken,
  COALESCE(aei.days_vacation_acquired - v.days_vacation_absence - v.days_vacation_cash_out, 0) AS days_balance, 
  COALESCE(aei.days_vacation_acquired - v.days_vacation_absence - v.days_vacation_cash_out, 0) <> 0 AS has_available_days, 
  aei.type_or_status = 'FECHADO' AS is_accrual_period_closed,
  NOW() AS ts_load
FROM
  datalake_pin_core_clean.assignment_extra_info AS aei
INNER JOIN 
  datalake_employee_registration.identifier_mapping AS ei
    ON ei.id_assignment = aei.id_assignment
LEFT JOIN
  vacation AS v
    ON aei.period = v.period
    AND ei.id_period_of_service = v.id_period_of_service
WHERE
  ei.assignment_type IN ('C', 'E')
  AND aei.dt_effective_ended = DATE('4712-12-31')
  AND aei.information_type = 'Saldo de Férias'