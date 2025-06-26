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
  md.id_assignment,
  md.id_period_of_service,
  md.id_person,
  COALESCE(wr.registration, lr.legacy_registration) AS legacy_registration,
  md.assignment_number,
  md.assignment_type,
  emp_info.person_number,
  emp_info.full_name AS full_name,
  LOWER(ew.email_address) AS work_email,
  LOWER(eh.email_address) AS personal_email,
  ext.id_person IS NOT NULL AS is_user_test
FROM
  datalake_pin.movement_details AS md
LEFT JOIN
  datalake_hr_system.employee_info AS emp_info
    ON emp_info.id_person = md.id_person
LEFT JOIN
  emails AS ew
    ON md.id_person = ew.id_person
    AND ew.email_type = 'W1'
LEFT JOIN
  emails AS eh
    ON md.id_person = eh.id_person
    AND eh.email_type = 'H1'
LEFT JOIN
  datalake_gsheets_people_clean.legacy_registration AS lr
    ON LOWER(lr.work_email) = LOWER(ew.email_address)
LEFT JOIN
  datalake_hr_system_custom_clean.workers_registration AS wr
    ON md.assignment_number = wr.assignment_number
LEFT JOIN
  external_identifiers AS ext
    ON ext.id_person = md.id_person
