WITH
assignments AS (
    SELECT DISTINCT
        id_assignment,
        id_period_of_service,
        id_person
    FROM
        datalake_hr_system.assignments
),
ranked_managers AS (
    SELECT
        mh.id_assignment,
        mh.id_manager_assignment,
        a.id_period_of_service AS id_period_of_service_manager,
        mh.separation_degree,
        ROW_NUMBER() OVER (
            PARTITION BY
                mh.id_assignment
            ORDER BY
                mh.separation_degree DESC
        ) as rn
    FROM
        datalake_hr_system.management_hierarchy AS mh
    LEFT JOIN
        assignments AS a
            ON a.id_assignment = mh.id_manager_assignment
),
managers_long AS (
    SELECT
        id_assignment,
        MAX(
            CASE
                WHEN rn = 1 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_0,
        MAX(
            CASE
                WHEN rn = 2 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_1,
        MAX(
            CASE
                WHEN rn = 3 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_2,
        MAX(
            CASE
                WHEN rn = 4 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_3,
        MAX(
            CASE
                WHEN rn = 5 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_4,
        MAX(
            CASE
                WHEN rn = 6 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_5,
        MAX(
            CASE
                WHEN rn = 7 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_6,
        MAX(
            CASE
                WHEN rn = 8 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_7,
        MAX(
            CASE
                WHEN rn = 9 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_8,
        MAX(
            CASE
                WHEN rn = 10 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_9
    FROM
        ranked_managers
    GROUP BY
        id_assignment
),
hr_system_workers AS (
    SELECT
      w.id_person,
      a.id_period_of_service,
      w.names,
      w.emails
    FROM
      datalake_hr_system_clean.workers AS w
    LEFT JOIN
      assignments AS a
        ON a.id_person = w.id_person
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
    MD5(
      CONCAT(
        COALESCE(sk_assignment_leadership_order_0, -1),
        COALESCE(sk_assignment_leadership_order_1, -1),
        COALESCE(sk_assignment_leadership_order_2, -1),
        COALESCE(sk_assignment_leadership_order_3, -1),
        COALESCE(sk_assignment_leadership_order_4, -1),
        COALESCE(sk_assignment_leadership_order_5, -1),
        COALESCE(sk_assignment_leadership_order_6, -1),
        COALESCE(sk_assignment_leadership_order_7, -1),
        COALESCE(sk_assignment_leadership_order_8, -1),
        COALESCE(sk_assignment_leadership_order_9, -1)
      )
    ) AS sk_hierarchy,
    sk_assignment_leadership_order_0,
    sk_assignment_leadership_order_1,
    sk_assignment_leadership_order_2,
    sk_assignment_leadership_order_3,
    sk_assignment_leadership_order_4,
    sk_assignment_leadership_order_5,
    sk_assignment_leadership_order_6,
    sk_assignment_leadership_order_7,
    sk_assignment_leadership_order_8,
    sk_assignment_leadership_order_9,
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
  managers_long AS ml
LEFT JOIN
  worker_information AS wi0
    ON wi0.id_period_of_service = ml.sk_assignment_leadership_order_0
LEFT JOIN
  worker_information AS wi1
    ON wi1.id_period_of_service = ml.sk_assignment_leadership_order_1
LEFT JOIN
  worker_information AS wi2
    ON wi2.id_period_of_service = ml.sk_assignment_leadership_order_2
LEFT JOIN
  worker_information AS wi3
    ON wi3.id_period_of_service = ml.sk_assignment_leadership_order_3
LEFT JOIN
  worker_information AS wi4
    ON wi4.id_period_of_service = ml.sk_assignment_leadership_order_4
LEFT JOIN
  worker_information AS wi5
    ON wi5.id_period_of_service = ml.sk_assignment_leadership_order_5
LEFT JOIN
  worker_information AS wi6
    ON wi6.id_period_of_service = ml.sk_assignment_leadership_order_6
LEFT JOIN
  worker_information AS wi7
    ON wi7.id_period_of_service = ml.sk_assignment_leadership_order_7
LEFT JOIN
  worker_information AS wi8
    ON wi8.id_period_of_service = ml.sk_assignment_leadership_order_8
LEFT JOIN
  worker_information AS wi9
    ON wi9.id_period_of_service = ml.sk_assignment_leadership_order_9
