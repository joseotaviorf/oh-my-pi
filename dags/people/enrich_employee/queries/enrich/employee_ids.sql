WITH
external_identifiers AS (
  SELECT DISTINCT
    id_person
  FROM
    datalake_hr_system_clean.workers AS w
  LATERAL VIEW
    EXPLODE(w.external_identifiers) AS e
  WHERE
    e.ExternalIdentifierType = 'ID_ONDA1'
),
emails AS (
  SELECT
    id_person,
    w.dt_effective,
    e.EmailAddress AS email_address,
    e.EmailType AS email_type,
    e.LastUpdateDate
  FROM
    datalake_hr_system_clean.workers AS w
  LATERAL VIEW
    EXPLODE(w.emails) AS e
  WHERE
    e.ToDate IS NULL OR e.ToDate = '4712-12-31'
  QUALIFY
    w.dt_effective = MAX(w.dt_effective) OVER (PARTITION BY id_person)
    AND e.LastUpdateDate = MAX(e.LastUpdateDate) OVER (PARTITION BY id_person, email_type)
)
SELECT DISTINCT
  a.id_assignment,
  a.id_period_of_service,
  a.id_person,
  COALESCE(wr.registration, lr.legacy_registration) AS legacy_registration,
  a.assignment_number,
  a.assignment_type,
  emp_info.person_number,
  emp_info.full_name AS full_name,
  LOWER(ew.email_address) AS work_email,
  LOWER(eh.email_address) AS personal_email,
  ext.id_person IS NOT NULL AS is_user_test
FROM
  datalake_hr_system.assignments AS a
LEFT JOIN
  datalake_hr_system.employee_info AS emp_info
    ON emp_info.id_person = a.id_person
LEFT JOIN
  emails AS ew
    ON a.id_person = ew.id_person
    AND ew.email_type = 'W1'
LEFT JOIN
  emails AS eh
    ON a.id_person = eh.id_person
    AND eh.email_type = 'H1'
LEFT JOIN
  datalake_gsheets_people_clean.legacy_registration lr
    ON LOWER(lr.work_email) = LOWER(ew.email_address)
LEFT JOIN
  datalake_hr_system_custom_clean.workers_registration wr
    ON a.assignment_number = wr.assignment_number
LEFT JOIN
  external_identifiers AS ext
    ON ext.id_person = a.id_person
