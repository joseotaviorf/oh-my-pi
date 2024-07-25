WITH hr_system_workers AS (
    SELECT
        id_person,
        person_number,
        birth_town,
        birth_region,
        birth_country,
        birth_country_name,
        dt_birth,
        national_identifiers,
        ethnicities,
        legislative_info,
        names,
        workers_dff,
        religions,
        external_identifiers
    FROM
        datalake_hr_system_clean.workers 
    QUALIFY dt_effective = MAX(dt_effective) OVER (PARTITION BY id_person)
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
        national_identifiers['NationalIdentifierId']     AS id_national_identifier,
        national_identifiers['NationalIdentifierNumber'] AS national_identifier_number,
        national_identifiers['NationalIdentifierType']   AS national_identifier_type,
        national_identifiers['nationalIdentifiersDFF']   AS national_identifiers_dff
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
        national_identifiers_dff["ufDeEmissao"]    AS issuing_state,
        national_identifiers_dff["orgaoDeEmissao"] AS issuing_authority
    FROM
        national_identifiers_dff_step1
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
), cte_enrich_demographic_attributes AS (
  SELECT 
    id_person,
    ctps_number,
    ctps_series,
    issuing_state_ctps,
    vote_registration_number,
    electoral_zone,
    polling_station,
    marital_status,
    highest_education_level,
    has_disability
  FROM datalake_hr_system.demographic_attributes
  QUALIFY 
    ts_last_update = MAX(ts_last_update) OVER (PARTITION BY id_person)
)
SELECT
    --  ids
    workers.id_person AS sk_employee,
    -- -- non metric
    workers.person_number,
    -- -- name information,
    names.first_name,
    names.last_name,
    names.full_name,
    names.name_information_15 AS first_social_name,
    names.name_information_16 AS last_social_name,
    -- -- birth info,
    workers.birth_town,
    workers.birth_region AS birth_state,
    workers.birth_country,
    -- -- docs info,
    ni2_cpf.national_identifier_number AS cpf,
    ni2_rg.national_identifier_number AS rg,
    ni2_pis.national_identifier_number AS pis,
    nidff.issuing_state AS issuing_state_rg,
    nidff.issuing_authority AS issuing_authority_rg,
    da.ctps_number,
    da.ctps_series,
    da.issuing_state_ctps,
    da.vote_registration_number,
    da.electoral_zone,
    da.polling_station,
    -- -- personal info,
    wdff.mother_name,
    wdff.father_name,
    COALESCE(da.marital_status, '-1') AS marital_status_code,
    CASE
        WHEN marital_status = 'C' THEN 'Casado(a)'
        WHEN marital_status = 'D' THEN 'Divorciado(a)'
        WHEN marital_status = 'M' THEN 'União Estável'
        WHEN marital_status = 'O' THEN 'Outros'
        WHEN marital_status = 'Q' THEN 'Desquitado(a) / Separado(a)'
        WHEN marital_status = 'S' THEN 'Solteiro'
        WHEN marital_status = 'V' THEN 'Viúvo(a)'
        WHEN marital_status = 'L' THEN 'Legalmente separado'
        WHEN marital_status = 'N' THEN 'Não informado'
        WHEN marital_status = 'ORA_HRX_SEP' THEN 'Separado(a)'
        ELSE '-1'
    END AS marital_status_description,
    COALESCE(da.highest_education_level, '-1') AS highest_education_level_code,
    CASE
        WHEN da.highest_education_level = '10' THEN 'Analfabeto, inclusive o que, embora tenha recebido instrução, não se alfabetizou'
        WHEN da.highest_education_level = '13' THEN 'Doutorado incompleto'
        WHEN da.highest_education_level = '20' THEN 'Até o 5º ano incompleto do Ensino Fundamental'
        WHEN da.highest_education_level = '25' THEN '5º ano completo do Ensino Fundamental'
        WHEN da.highest_education_level = '30' THEN 'Do 6º ao 9º ano do Ensino Fundamental incompleto'
        WHEN da.highest_education_level = '35' THEN 'Ensino Fundamental completo'
        WHEN da.highest_education_level = '40' THEN 'Ensino Médio incompleto'
        WHEN da.highest_education_level = '45' THEN 'Ensino Médio completo'
        WHEN da.highest_education_level = '50' THEN 'Educação Superior incompleta'
        WHEN da.highest_education_level = '55' THEN 'Educação Superior completa'
        WHEN da.highest_education_level = '65' THEN 'Mestrado completo'
        WHEN da.highest_education_level = '75' THEN 'Doutorado completo'
        WHEN da.highest_education_level = '85' THEN 'Pós-graduação completa'
        WHEN da.highest_education_level = '800' THEN 'Mestrado incompleto'
        WHEN da.highest_education_level = '801' THEN 'Pós-graduação incompleta'
        WHEN da.highest_education_level = '803' THEN 'Tecnólogo incompleto'
        WHEN da.highest_education_level = '805' THEN 'Tecnólogo completo'
        WHEN da.highest_education_level = '807' THEN 'Técnico incompleto'
        WHEN da.highest_education_level = '809' THEN 'Técnico completo'
        WHEN da.highest_education_level = '811' THEN 'Não Informado'
        WHEN da.highest_education_level = 'ORA_HRX_HIGHER_UNI' THEN 'Universitário superior'
        ELSE '-1'
    END AS highest_education_level_description,
    CASE 
        WHEN DATEDIFF(current_date(), workers.dt_birth) < 21 * 365 THEN 'menos de 21 anos'
        WHEN DATEDIFF(current_date(), workers.dt_birth) BETWEEN 21 * 365 AND 25 * 365 THEN 'de 21 até 25 anos'
        WHEN DATEDIFF(current_date(), workers.dt_birth) BETWEEN 26 * 365 AND 30 * 365 THEN 'de 26 até 30 anos'
        WHEN DATEDIFF(current_date(), workers.dt_birth) BETWEEN 31 * 365 AND 35 * 365 THEN 'de 31 até 35 anos'
        WHEN DATEDIFF(current_date(), workers.dt_birth) BETWEEN 36 * 365 AND 40 * 365 THEN 'de 36 até 40 anos'
        WHEN DATEDIFF(current_date(), workers.dt_birth) BETWEEN 41 * 365 AND 45 * 365 THEN 'de 41 até 45 anos'
        WHEN DATEDIFF(current_date(), workers.dt_birth) BETWEEN 46 * 365 AND 50 * 365 THEN 'de 46 até 50 anos'
        WHEN DATEDIFF(current_date(), workers.dt_birth) BETWEEN 51 * 365 AND 55 * 365 THEN 'de 51 até 55 anos'
        ELSE 'mais de 55 anos'
    END AS age_range,
    -- -- dates
    DATE(workers.dt_birth) AS dt_birth,
    NOW() AS ts_load
FROM
    hr_system_workers AS workers
LEFT JOIN 
    cte_enrich_demographic_attributes AS da 
        ON workers.id_person = da.id_person
LEFT JOIN 
    names 
        ON workers.id_person = names.id_person
LEFT JOIN 
    workers_dff AS wdff 
        ON workers.id_person = wdff.id_person
LEFT JOIN 
    external_identifiers ei 
        ON workers.id_person = ei.id_person
LEFT JOIN 
    national_identifiers_step2 ni2_cpf 
        ON workers.id_person = ni2_cpf.id_person
        AND ni2_cpf.national_identifier_type = 'CPF'
LEFT JOIN 
    national_identifiers_step2 ni2_rg 
        ON workers.id_person = ni2_rg.id_person
        AND ni2_rg.national_identifier_type = 'RG'
LEFT JOIN 
    national_identifiers_step2 ni2_pis 
        ON workers.id_person = ni2_pis.id_person
        AND ni2_pis.national_identifier_type = 'PIS'
LEFT JOIN 
    national_identifiers_dff nidff 
        ON workers.id_person = nidff.id_person
        AND ni2_rg.id_national_identifier = nidff.id_national_identifier
WHERE ei.id_person IS NULL