WITH
hr_system_workers AS (
    SELECT
      id_person,
      names,
      emails
    FROM
      datalake_hr_system_clean.workers
    QUALIFY
      dt_effective = MAX(dt_effective) OVER (PARTITION BY id_person)
),
names_step1 AS (
  SELECT
    id_person,
    EXPLODE(names) AS names
  FROM
    hr_system_workers
),
names AS (
  SELECT
    id_person,
    names["FullName"] AS full_name
  FROM
    names_step1
),
emails_step1 AS (
    SELECT
      id_person,
      EXPLODE(emails) AS emails
    FROM
      hr_system_workers
  ),
  emails AS (
    SELECT
      id_person,
      emails['EmailAddress'] AS email_address,
      emails['EmailType'] AS email_type
    FROM
      emails_step1
    WHERE
      emails['ToDate'] IS NULL
      OR emails['ToDate'] = '4712-12-31'
    QUALIFY
        emails['LastUpdateDate'] = MAX(emails['LastUpdateDate']) OVER (PARTITION BY id_person, emails['EmailType']))
SELECT DISTINCT
  a.id_assignment,
  a.id_period_of_service,
  a.id_person,
  a.assignment_number,
  UPPER(names.full_name) AS full_name,
  LOWER(ew.email_address) AS work_email,
  LOWER(eh.email_address) AS personal_email
FROM
  datalake_hr_system.assignments AS a
LEFT JOIN
  names
    ON names.id_person = a.id_person
LEFT JOIN
  emails AS ew
    ON a.id_person = ew.id_person
    AND ew.email_type = 'W1'
LEFT JOIN
  emails AS eh
    ON a.id_person = eh.id_person
    AND eh.email_type = 'H1'
