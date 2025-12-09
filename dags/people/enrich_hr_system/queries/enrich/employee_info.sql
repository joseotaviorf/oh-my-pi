WITH hr_system_workers AS (
  SELECT
    id_person,
    person_number,
    birth_town,
    birth_region,
    birth_country,
    birth_country_name,
    dt_birth,
    names,
    workers_dff,
    external_identifiers
  FROM
    datalake_hr_system_clean.workers 
  QUALIFY 
    dt_effective = MAX(dt_effective) OVER (
      PARTITION BY
        id_person
    )
),
external_identifiers_step1 AS (
  SELECT
    id_person,
    EXPLODE (external_identifiers) external_identifiers
  FROM
    hr_system_workers
),
external_identifiers AS (
  SELECT
    id_person
  FROM
    external_identifiers_step1
  WHERE
    external_identifiers['ExternalIdentifierType'] = 'ID_ONDA1'
),
names_step1 AS (
  SELECT
    id_person,
    EXPLODE (names) names
  FROM
    hr_system_workers
),
names AS (
  SELECT
    id_person,
    names["FirstName"] AS first_name,
    names["FullName"] AS full_name,
    names["LastName"] AS last_name,
    names["NameInformation15"] AS name_information_15,
    names["NameInformation16"] AS name_information_16
  FROM
    names_step1
),
workers_dff_step1 AS (
  SELECT
    id_person,
    EXPLODE (workers_dff) workers_dff
  FROM
    hr_system_workers
),
workers_dff AS (
  SELECT
    id_person,
    workers_dff["nomeDaMae"] AS mother_name,
    workers_dff["nomeDoPai"] AS father_name
  FROM
    workers_dff_step1
)
SELECT
  --  ids
  workers.id_person,
  -- -- non metric
  workers.person_number,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(REGEXP_REPLACE(names.first_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' ')
    )
  ) AS first_name,
  INITCAP(
    TRIM(REGEXP_REPLACE(REGEXP_REPLACE(names.last_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '))
  ) AS last_name,
  INITCAP(
    TRIM(REGEXP_REPLACE(REGEXP_REPLACE(names.full_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '))
  ) AS full_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(REGEXP_REPLACE(names.name_information_15, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' ')
    )
  ) AS first_social_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(REGEXP_REPLACE(names.name_information_16, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' ')
    )
  ) AS last_social_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(REGEXP_REPLACE(wdff.mother_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' ')
    )
  ) AS mother_name,
  INITCAP(
    TRIM(
      REGEXP_REPLACE(REGEXP_REPLACE(wdff.father_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' ')
    )
  ) AS father_name,
  -- -- birth info
  workers.birth_town,
  workers.birth_region AS birth_state,
  workers.birth_country,
  DATE(workers.dt_birth) AS dt_birth,
  NOW() AS ts_load
FROM
  hr_system_workers AS workers
  LEFT JOIN 
    names 
      ON workers.id_person = names.id_person
  LEFT JOIN 
    workers_dff AS wdff 
      ON workers.id_person = wdff.id_person
  LEFT JOIN 
    external_identifiers ei 
      ON workers.id_person = ei.id_person
WHERE
  ei.id_person IS NULL