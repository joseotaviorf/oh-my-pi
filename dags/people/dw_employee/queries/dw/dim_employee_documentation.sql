WITH hr_system_workers AS (
  SELECT
    id_person,
    national_identifiers
  FROM
    datalake_hr_system_clean.workers 
  QUALIFY DENSE_RANK() OVER (
      PARTITION BY id_person
      ORDER BY
        dt_effective
    ) = 2
),
national_identifiers_step1 AS (
  SELECT
    id_person,
    EXPLODE (national_identifiers) national_identifiers
  FROM
    hr_system_workers
),
national_identifiers_step2 AS (
  SELECT
    id_person,
    national_identifiers ['NationalIdentifierId'] AS id_national_identifier,
    national_identifiers ['NationalIdentifierNumber'] AS national_identifier_number,
    national_identifiers ['NationalIdentifierType'] AS national_identifier_type,
    national_identifiers ['nationalIdentifiersDFF'] AS national_identifiers_dff,
    TO_TIMESTAMP(
      SUBSTR(
        REPLACE(national_identifiers ['LastUpdateDate'], 'T', ' '),
        0,
        19
      ),
      'yyyy-MM-dd HH:mm:ss'
    ) AS ts_last_update
  FROM
    national_identifiers_step1
),
national_identifiers_dff_step1 AS (
  SELECT
    id_person,
    id_national_identifier,
    EXPLODE (national_identifiers_dff) AS national_identifiers_dff
  FROM
    national_identifiers_step2
),
national_identifiers_dff AS (
  SELECT
    id_person,
    id_national_identifier,
    national_identifiers_dff ["ufDeEmissao"] AS issuing_state,
    national_identifiers_dff ["orgaoDeEmissao"] AS issuing_authority
  FROM
    national_identifiers_dff_step1
)
SELECT
  w.id_person AS sk_employee,
  ni2_cpf.national_identifier_number AS cpf,
  ni2_pis.national_identifier_number AS pis,
  ni2_rg.national_identifier_number AS rg,
  nidff.issuing_state AS issuing_state_rg,
  nidff.issuing_authority AS issuing_authority_rg,
  da.ctps_number,
  da.ctps_series,
  da.issuing_state_ctps,
  da.vote_registration_number,
  da.electoral_zone,
  da.polling_station,
  GREATEST(
    DATE(ni2_cpf.ts_last_update),
    DATE(ni2_rg.ts_last_update),
    DATE(ni2_pis.ts_last_update),
    da.dt_effective_start
  ) AS ts_last_update,
  NOW() AS ts_load
FROM
  hr_system_workers AS w
LEFT JOIN 
  national_identifiers_step2 ni2_cpf 
    ON w.id_person = ni2_cpf.id_person
  AND ni2_cpf.national_identifier_type = 'CPF'
LEFT JOIN 
  national_identifiers_step2 ni2_rg 
    ON w.id_person = ni2_rg.id_person
    AND ni2_rg.national_identifier_type = 'RG'
LEFT JOIN 
  national_identifiers_step2 ni2_pis 
    ON w.id_person = ni2_pis.id_person
    AND ni2_pis.national_identifier_type = 'PIS'
LEFT JOIN 
  national_identifiers_dff nidff 
    ON w.id_person = nidff.id_person
    AND ni2_rg.id_national_identifier = nidff.id_national_identifier
LEFT JOIN 
  datalake_hr_system.demographic_attributes AS da 
    ON w.id_person = da.id_person
    AND da.legislation_code = 'BR'
WHERE
  GREATEST(
    DATE(ni2_cpf.ts_last_update),
    DATE(ni2_rg.ts_last_update),
    DATE(ni2_pis.ts_last_update),
    da.dt_effective_start
  ) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')