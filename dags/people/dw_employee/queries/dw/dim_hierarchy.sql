WITH
hr_system_workers AS (
    SELECT
      w.id_person,
      ei.id_period_of_service,
      w.names,
      w.emails
    FROM
      datalake_hr_system_clean.workers AS w
    LEFT JOIN
      datalake_hr_system.employee_ids AS ei
        ON ei.id_person = w.id_person
    QUALIFY
      dt_effective = MAX(dt_effective)
        OVER (PARTITION BY w.id_person)
),
names_step1 AS (
  SELECT
    id_period_of_service,
    EXPLODE (names) names
  FROM
    hr_system_workers
),
names AS (
  SELECT
    id_period_of_service,
    names["FullName"] AS full_name
  FROM
    names_step1
),
emails_step1 AS (
    SELECT
      id_period_of_service,
      EXPLODE (emails) emails
    FROM
      hr_system_workers
  ),
  emails AS (
    SELECT
      id_period_of_service,
      emails['EmailAddress'] AS email_address
    FROM
      emails_step1
    WHERE
      (emails['ToDate'] IS NULL
      OR emails['ToDate'] = '4712-12-31')
      AND emails['EmailType'] = 'W1'
    QUALIFY emails['LastUpdateDate'] = MAX(emails['LastUpdateDate']) OVER (
        PARTITION BY
          id_period_of_service,
          emails['EmailType']
      )
  ),
  worker_information AS (
    SELECT
      names.id_period_of_service,
      names.full_name,
      emails.email_address AS email
    FROM
      names
    LEFT JOIN
      emails
        ON names.id_period_of_service = emails.id_period_of_service
  )

SELECT DISTINCT
    h.sk_hierarchy,
    h.sk_assignment_leadership_order_0,
    h.sk_assignment_leadership_order_1,
    h.sk_assignment_leadership_order_2,
    h.sk_assignment_leadership_order_3,
    h.sk_assignment_leadership_order_4,
    h.sk_assignment_leadership_order_5,
    h.sk_assignment_leadership_order_6,
    h.sk_assignment_leadership_order_7,
    h.sk_assignment_leadership_order_8,
    h.sk_assignment_leadership_order_9,
    wi0.full_name AS full_name_leadership_0,
    wi1.full_name AS full_name_leadership_1,
    wi2.full_name AS full_name_leadership_2,
    wi3.full_name AS full_name_leadership_3,
    wi4.full_name AS full_name_leadership_4,
    wi5.full_name AS full_name_leadership_5,
    wi6.full_name AS full_name_leadership_6,
    wi7.full_name AS full_name_leadership_7,
    wi8.full_name AS full_name_leadership_8,
    wi9.full_name AS full_name_leadership_9,
    wi0.email AS email_leadership_0,
    wi1.email AS email_leadership_1,
    wi2.email AS email_leadership_2,
    wi3.email AS email_leadership_3,
    wi4.email AS email_leadership_4,
    wi5.email AS email_leadership_5,
    wi6.email AS email_leadership_6,
    wi7.email AS email_leadership_7,
    wi8.email AS email_leadership_8,
    wi9.email AS email_leadership_9

FROM
  datalake_hr_system.hierarchy_ids AS h
LEFT JOIN
  worker_information AS wi0
    ON wi0.id_period_of_service = h.sk_assignment_leadership_order_0
LEFT JOIN
  worker_information AS wi1
    ON wi1.id_period_of_service = h.sk_assignment_leadership_order_1
LEFT JOIN
  worker_information AS wi2
    ON wi2.id_period_of_service = h.sk_assignment_leadership_order_2
LEFT JOIN
  worker_information AS wi3
    ON wi3.id_period_of_service = h.sk_assignment_leadership_order_3
LEFT JOIN
  worker_information AS wi4
    ON wi4.id_period_of_service = h.sk_assignment_leadership_order_4
LEFT JOIN
  worker_information AS wi5
    ON wi5.id_period_of_service = h.sk_assignment_leadership_order_5
LEFT JOIN
  worker_information AS wi6
    ON wi6.id_period_of_service = h.sk_assignment_leadership_order_6
LEFT JOIN
  worker_information AS wi7
    ON wi7.id_period_of_service = h.sk_assignment_leadership_order_7
LEFT JOIN
  worker_information AS wi8
    ON wi8.id_period_of_service = h.sk_assignment_leadership_order_8
LEFT JOIN
  worker_information AS wi9
    ON wi9.id_period_of_service = h.sk_assignment_leadership_order_9
