WITH
users_base AS (
  SELECT
    id AS id_user,
    LOWER(TRIM(work_email)) AS work_email
  FROM
    datalake_degreed_clean.users
),
person_from_completions AS (
  SELECT
    id_user,
    MAX(person_number) AS person_number
  FROM
    datalake_learning.content_completions
  WHERE
    person_number IS NOT NULL
  GROUP BY
    id_user
),
person_from_mapping AS (
  SELECT
    work_email,
    MAX(person_number) AS person_number
  FROM
    datalake_people.identifier_mapping
  WHERE
    work_email IS NOT NULL
    AND person_number IS NOT NULL
  GROUP BY
    work_email
)
SELECT
  ub.id_user,
  ub.work_email,
  COALESCE(pfc.person_number, pfm.person_number) AS person_number,
  NOW() AS ts_load
FROM
  users_base AS ub
LEFT JOIN
  person_from_completions AS pfc
  ON pfc.id_user = ub.id_user
LEFT JOIN
  person_from_mapping AS pfm
  ON pfm.work_email = ub.work_email
