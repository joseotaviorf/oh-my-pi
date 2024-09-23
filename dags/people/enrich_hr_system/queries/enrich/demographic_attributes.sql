WITH hr_system_workers AS (
  SELECT
    id_person,
    legislative_info,
    external_identifiers,
    ethnicities,
    religions
  FROM
    datalake_hr_system_clean.workers 
QUALIFY 
    DENSE_RANK() OVER (
      PARTITION BY id_person
      ORDER BY
        dt_effective
    ) = 2
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
    external_identifiers ['ExternalIdentifierType'] = 'ID_ONDA1'
),
legislative_info_step1 AS (
  SELECT
    id_person,
    EXPLODE (legislative_info) legislative_info
  FROM
    hr_system_workers
),
legislative_info AS (
  SELECT
    id_person,
    legislative_info ['PersonLegislativeId'] AS id_person_legislative,
    legislative_info ['MaritalStatus'] AS marital_status,
    legislative_info ['Gender'] AS gender,
    legislative_info ['HighestEducationLevel'] AS highest_education_level,
    legislative_info ['legislativeInfoDFF'] AS legislative_info_dff,
    legislative_info ['legislativeInfoDDF'] AS legislative_info_ddf,
    legislative_info ['LegislationCode'] AS legislation_code,
    TO_TIMESTAMP(
      SUBSTR(
        REPLACE(legislative_info ['CreationDate'], 'T', ' '),
        0,
        19
      ),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_created,
    TO_TIMESTAMP(
      SUBSTR(
        REPLACE(legislative_info ['LastUpdateDate'], 'T', ' '),
        0,
        19
      ),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_update,
    DATE(legislative_info ['EffectiveStartDate']) AS dt_effective_start,
    DATE(legislative_info ['EffectiveEndDate']) AS dt_effective_end
  FROM
    legislative_info_step1
),
legislative_info_ddf_step1 AS (
  SELECT
    id_person,
    id_person_legislative,
    EXPLODE (legislative_info_ddf) AS legislative_info_ddf
  FROM
    legislative_info
),
legislative_info_ddf AS (
  SELECT
    id_person,
    id_person_legislative,
    legislative_info_ddf ["ctpsNumber"] AS ctps_number,
    legislative_info_ddf ["ctpsSeries"] AS ctps_series,
    legislative_info_ddf ["issuingState"] AS issuing_state_ctps
  FROM
    legislative_info_ddf_step1
),
legislative_info_dff_step1 AS (
  SELECT
    id_person,
    id_person_legislative,
    EXPLODE (legislative_info_dff) AS legislative_info_dff
  FROM
    legislative_info
),
legislative_info_dff AS (
  SELECT
    id_person,
    id_person_legislative,
    legislative_info_dff ["numeroDoTituloDeEleitor"] AS vote_registration_number,
    legislative_info_dff ["zonaEleitoralDoTitulo"] AS electoral_zone,
    legislative_info_dff ["secaoEleitoralDoTitulo"] AS polling_station,
    legislative_info_dff ["possuiAlgumaDeficiencia"] AS has_disability,
    legislative_info_dff ["orientacaoSexual"] AS sexual_orientation,
    legislative_info_dff ["genero"] AS gender_identity,
    legislative_info_dff ["neurodiversidade"] AS neurodiversity,
    legislative_info_dff ["__FLEX_Context"] AS nationality,
    legislative_info_dff ["desejaReceberAdiantamentoSalar"] AS has_salary_advance,
    legislative_info_dff ["situacaoNoPais"] AS country_situation,
    legislative_info_dff ["tipoDeMoradia"] AS housing_type,
    legislative_info_dff ["comoSeJuntouAoQuintoandar"] AS quinto_andar_joining_method,
    legislative_info_dff ["deficienciaAutodeclaracao"] AS disability_self_declaration_code,
    legislative_info_dff ["deficienciaAutodeclaracao_Display"] AS disability_self_declaration_description
  FROM
    legislative_info_dff_step1
),
ethnicities_step1 AS (
  SELECT
    id_person,
    EXPLODE (ethnicities) ethnicities
  FROM
    hr_system_workers
),
ethnicities AS (
  SELECT
    id_person,
    ethnicities ['EthnicityId'] AS id_ethnicity,
    ethnicities ['Ethnicity'] AS ethnicity,
    ethnicities ['LegislationCode'] AS legislation_code,
    TO_TIMESTAMP(
      SUBSTR(
        REPLACE(ethnicities ['CreationDate'], 'T', ' '),
        0,
        19
      ),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_created,
    TO_TIMESTAMP(
      SUBSTR(
        REPLACE(ethnicities ['LastUpdateDate'], 'T', ' '),
        0,
        19
      ),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_update
  FROM
    ethnicities_step1
  WHERE
    ethnicities ['PrimaryFlag'] = 'true' QUALIFY ethnicities ['LastUpdateDate'] = MAX(ethnicities ['LastUpdateDate']) OVER (PARTITION BY id_person)
),
religions_step1 AS (
  SELECT
    id_person,
    EXPLODE (religions) religions
  FROM
    hr_system_workers
),
religions AS (
  SELECT
    id_person,
    religions ['ReligionId'] AS id_religion,
    religions ["Religion"] AS religion,
    religions ['LegislationCode'] AS legislation_code,
    TO_TIMESTAMP(
      SUBSTR(
        REPLACE(religions ['CreationDate'], 'T', ' '),
        0,
        19
      ),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_created,
    TO_TIMESTAMP(
      SUBSTR(
        REPLACE(religions ['LastUpdateDate'], 'T', ' '),
        0,
        19
      ),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_update
  FROM
    religions_step1
  WHERE
    religions ["PrimaryFlag"] = 'true' QUALIFY religions ['LastUpdateDate'] = MAX(religions ['LastUpdateDate']) OVER (PARTITION BY id_person)
)
SELECT
  -- ids
  li.id_person,
  -- non-ids
  md5(
    concat(
      COALESCE(eth.ethnicity, '-1'),
      COALESCE(lidff.gender_identity, '-1'),
      COALESCE(lidff.sexual_orientation, '-1'),
      COALESCE(lidff.neurodiversity, '-1'),
      COALESCE(rel.religion,'-1'),
      COALESCE(lidff.country_situation, '-1'),
      COALESCE(lidff.housing_type, '-1'),
      COALESCE(lidff.quinto_andar_joining_method, '-1'),
      COALESCE(li.legislation_code, '-1')
    )
  ) AS sk_demographic_information, 
  li.id_person_legislative,
  eth.id_ethnicity,
  rel.id_religion,
  -- non-metrics
  li.marital_status,
  li.gender,
  li.highest_education_level,
  li.legislation_code,
  lidff.sexual_orientation,
  lidff.gender_identity,
  lidff.neurodiversity,
  lidff.nationality,
  lidff.disability_self_declaration_code,
  lidff.disability_self_declaration_description,
  liddf.ctps_number,
  liddf.ctps_series,
  liddf.issuing_state_ctps,
  lidff.vote_registration_number,
  lidff.electoral_zone,
  lidff.polling_station,
  lidff.country_situation,
  lidff.housing_type,
  lidff.quinto_andar_joining_method,
  eth.ethnicity,
  rel.religion,
  -- metrics
  CASE
    WHEN lidff.has_disability = 'Sim' THEN TRUE
    WHEN lidff.has_disability = 'Não' THEN FALSE
    ELSE NULL
  END has_disability,
  CASE
    WHEN lidff.has_salary_advance = 'S' THEN TRUE
    WHEN lidff.has_salary_advance = 'N' THEN FALSE
    ELSE NULL
  END has_salary_advance,
  -- dates
  li.dt_effective_start AS dt_effective_start,
  li.dt_effective_end AS dt_effective_end,
  -- timestamps
  LEAST(li.ts_created, eth.ts_created, rel.ts_created) AS ts_created,
  GREATEST(
    li.ts_last_update,
    eth.ts_last_update,
    rel.ts_last_update
  ) AS ts_last_update,
  NOW() AS ts_load
FROM
  legislative_info AS li
  LEFT JOIN legislative_info_ddf AS liddf 
      ON li.id_person = liddf.id_person
  AND li.id_person_legislative = liddf.id_person_legislative
  LEFT JOIN legislative_info_dff AS lidff ON li.id_person = lidff.id_person
  AND li.id_person_legislative = lidff.id_person_legislative
  LEFT JOIN ethnicities AS eth ON li.id_person = eth.id_person
  AND li.legislation_code = eth.legislation_code
  LEFT JOIN religions AS rel ON li.id_person = rel.id_person
  AND li.legislation_code = rel.legislation_code
  LEFT JOIN external_identifiers AS ei ON li.id_person = ei.id_person
WHERE
  ei.id_person IS NULL