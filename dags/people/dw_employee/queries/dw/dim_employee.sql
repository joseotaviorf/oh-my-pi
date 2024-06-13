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
        emails,
        addresses,
        names,
        workers_dff,
        phones,
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
        ethnicities['EthnicityId']     AS id_ethnicity,
        ethnicities['Ethnicity']       AS ethnicity,
        ethnicities['LegislationCode'] AS legislation_code
    FROM
        ethnicities_step1
    WHERE
        ethnicities['PrimaryFlag'] = 'true' 
    QUALIFY ethnicities['LastUpdateDate'] = MAX(ethnicities['LastUpdateDate']) OVER (PARTITION BY id_person)
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
        legislative_info['PersonLegislativeId']   AS id_person_legislative,
        legislative_info['MaritalStatus']         AS marital_status,
        legislative_info['Gender']                AS gender,
        legislative_info['HighestEducationLevel'] AS highest_education_level,
        legislative_info['legislativeInfoDFF']    AS legislative_info_dff,
        legislative_info['legislativeInfoDDF']    AS legislative_info_ddf,
        legislative_info['LegislationCode']       AS legislation_code
    FROM
        legislative_info_step1 
    QUALIFY legislative_info['LastUpdateDate'] = MAX(legislative_info['LastUpdateDate']) OVER (PARTITION BY id_person)
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
        legislative_info_ddf["ctpsNumber"]   AS ctps_number,
        legislative_info_ddf["ctpsSeries"]   AS ctps_series,
        legislative_info_ddf["issuingState"] AS issuing_state_ctps
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
        legislative_info_dff["numeroDoTituloDeEleitor"] AS  vote_registration_number,
        legislative_info_dff["zonaEleitoralDoTitulo"] AS  electoral_zone,
        legislative_info_dff["secaoEleitoralDoTitulo"] AS  polling_station,
        legislative_info_dff["possuiAlgumaDeficiencia"] AS  has_disability,
        legislative_info_dff["orientacaoSexual"] AS  sexual_orientation,
        legislative_info_dff["genero"] AS  genero,
        legislative_info_dff["neurodiversidade"] AS  neurodiversidade,
        legislative_info_dff["__FLEX_Context"] AS  nacionalidade,
        legislative_info_dff["desejaReceberAdiantamentoSalar"] AS has_salary_advance
    FROM
        legislative_info_dff_step1
),
legislative_info_data AS (
    SELECT
        li.id_person,
        li.marital_status,
        li.gender,
        li.highest_education_level,
        li.legislation_code,
        liddf.ctps_number,
        liddf.ctps_series,
        liddf.issuing_state_ctps,
        lidff.vote_registration_number,
        lidff.electoral_zone,
        lidff.polling_station,
        lidff.has_disability,
        lidff.sexual_orientation,
        lidff.genero,
        lidff.neurodiversidade,
        lidff.nacionalidade,
        lidff.has_salary_advance
    FROM
        legislative_info AS li
    LEFT JOIN 
        legislative_info_ddf AS liddf 
            ON li.id_person = liddf.id_person
            AND li.id_person_legislative = liddf.id_person_legislative
    LEFT JOIN 
        legislative_info_dff AS lidff 
            ON li.id_person = lidff.id_person
            AND li.id_person_legislative = lidff.id_person_legislative
),
emails_step1 AS (
    SELECT
        id_person,
        EXPLODE (emails) emails
    FROM
        hr_system_workers
),
emails AS (
    SELECT
        id_person,
        emails['EmailAddressId'] AS id_email_address,
        emails['EmailType'] AS email_type,
        emails['EmailAddress'] AS email_address,
        emails['PrimaryFlag'] AS primary_flag
    FROM
        emails_step1
    WHERE
        emails['ToDate'] IS NULL
        OR emails['ToDate'] = '4712-12-31' 
    QUALIFY emails['LastUpdateDate'] = MAX(emails['LastUpdateDate']) OVER (PARTITION BY id_person, emails['EmailType'])
),
addresses_step1 AS (
    SELECT
        id_person,
        EXPLODE (addresses) addresses
    FROM
        hr_system_workers
),
addresses AS (
    SELECT
        id_person,
        addresses['AddressId']AS id_address,
        addresses['AddlAddressAttribute3'] AS addl_address_attribute_3,
        addresses['AddressLine1'] AS address_line_1,
        addresses['AddressLine2'] AS address_line_2,
        addresses['AddressLine3'] AS address_line_3,
        addresses['AddressLine4'] AS address_line_4,
        addresses['PostalCode'] AS postal_code,
        addresses['TownOrCity'] AS town_or_city,
        addresses['Region2'] AS region_2,
        addresses['Country'] AS country
    FROM
        addresses_step1
    WHERE
        addresses['PrimaryFlag'] = 'true'
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
),
phones_step1 AS (
    SELECT
        id_person,
        EXPLODE (phones) AS phones
    FROM
        hr_system_workers
),
phones AS (
    SELECT
        id_person,
        phones['PhoneId'] AS id_phone,
        phones['CountryCodeNumber'] AS country_code_number,
        phones['AreaCode'] AS area_code,
        phones['PhoneNumber'] AS phone_number
    FROM
        phones_step1
    WHERE
        phones['PrimaryFlag'] = 'true'
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
        religions["Religion"] AS religion,
        religions['LegislationCode'] AS legislation_code
    FROM
        religions_step1
    WHERE
        religions["PrimaryFlag"] = 'true' 
    QUALIFY religions['LastUpdateDate'] = MAX(religions['LastUpdateDate']) OVER (PARTITION BY id_person)
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
    li.ctps_number,
    li.ctps_series,
    li.issuing_state_ctps,
    li.vote_registration_number,
    li.electoral_zone,
    li.polling_station,
    -- -- personal info,
    wdff.mother_name,
    wdff.father_name,
    COALESCE(ethnicities.ethnicity, '-1') AS ethnicity_code,
    CASE
        WHEN ethnicities.ethnicity = '1' THEN 'Indígena'
        WHEN ethnicities.ethnicity = '2' THEN 'Branca'
        WHEN ethnicities.ethnicity = '4' THEN 'Preta'
        WHEN ethnicities.ethnicity = '6' THEN 'Amarela'
        WHEN ethnicities.ethnicity = '8' THEN 'Parda'
        WHEN ethnicities.ethnicity = '9' THEN 'Não informado'
        WHEN ethnicities.ethnicity = '15' THEN 'Negro'
        WHEN ethnicities.ethnicity = 'ORA_HRX_MIXED' THEN 'Misto'
        WHEN ethnicities.ethnicity = '60' THEN 'Nativo'
        WHEN ethnicities.ethnicity = 'ORA_HRX_BRIN' THEN 'Índio Brasileiro'
        WHEN ethnicities.ethnicity = '20' THEN 'Moreno'
        ELSE '-1'
    END AS ethnicity_description,
    COALESCE(li.marital_status, '-1') AS marital_status_code,
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
    COALESCE(li.gender, '-1') AS gender,
    COALESCE(li.sexual_orientation, '-1') AS sexual_orientation,
    COALESCE(li.genero, '-1') AS gender_identity,
    COALESCE(li.neurodiversidade, '-1') AS neurodiversity,
    COALESCE(religions.religion, '-1') AS religion_code,
    CASE
        WHEN religions.religion = 'BUDDHIST' THEN 'Budismo'
        WHEN religions.religion = 'CHRISTIAN' THEN 'Cristã'
        WHEN religions.religion = 'HINDU' THEN 'Hinduísta'
        WHEN religions.religion = 'JEWISH' THEN 'Judaica'
        WHEN religions.religion = 'NONE' THEN 'Nenhuma'
        WHEN religions.religion = 'NOTSTATED' THEN 'Prefiro Não Informar'
        WHEN religions.religion = 'ORA_HRX_CATHOLICISM' THEN 'Catolicismo'
        WHEN religions.religion = 'OTHER' THEN 'Outra'
        WHEN religions.religion IS NULL THEN '-1'
        ELSE religions.religion
    END AS religion_description,
    COALESCE(li.highest_education_level, '-1') AS highest_education_level_code,
    CASE
        WHEN li.highest_education_level = '10' THEN 'Analfabeto, inclusive o que, embora tenha recebido instrução, não se alfabetizou'
        WHEN li.highest_education_level = '13' THEN 'Doutorado incompleto'
        WHEN li.highest_education_level = '20' THEN 'Até o 5º ano incompleto do Ensino Fundamental'
        WHEN li.highest_education_level = '25' THEN '5º ano completo do Ensino Fundamental'
        WHEN li.highest_education_level = '30' THEN 'Do 6º ao 9º ano do Ensino Fundamental incompleto'
        WHEN li.highest_education_level = '35' THEN 'Ensino Fundamental completo'
        WHEN li.highest_education_level = '40' THEN 'Ensino Médio incompleto'
        WHEN li.highest_education_level = '45' THEN 'Ensino Médio completo'
        WHEN li.highest_education_level = '50' THEN 'Educação Superior incompleta'
        WHEN li.highest_education_level = '55' THEN 'Educação Superior completa'
        WHEN li.highest_education_level = '65' THEN 'Mestrado completo'
        WHEN li.highest_education_level = '75' THEN 'Doutorado completo'
        WHEN li.highest_education_level = '85' THEN 'Pós-graduação completa'
        WHEN li.highest_education_level = '800' THEN 'Mestrado incompleto'
        WHEN li.highest_education_level = '801' THEN 'Pós-graduação incompleta'
        WHEN li.highest_education_level = '803' THEN 'Tecnólogo incompleto'
        WHEN li.highest_education_level = '805' THEN 'Tecnólogo completo'
        WHEN li.highest_education_level = '807' THEN 'Técnico incompleto'
        WHEN li.highest_education_level = '809' THEN 'Técnico completo'
        WHEN li.highest_education_level = '811' THEN 'Não Informado'
        WHEN li.highest_education_level = 'ORA_HRX_HIGHER_UNI' THEN 'Universitário superior'
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
    -- -- -- contacts,
    ew.email_address AS work_email,
    eh.email_address AS personal_email,
    phones.country_code_number,
    phones.area_code,
    phones.phone_number,
    -- -- address,
    CONCAT(addresses.addl_address_attribute_3, ' ', addresses.address_line_1) AS address,
    addresses.address_line_2 AS address_number,
    addresses.address_line_3 AS address_complement,
    addresses.address_line_4 AS address_district,
    addresses.postal_code AS address_zip_code,
    addresses.town_or_city AS address_city,
    addresses.region_2 AS address_state,
    addresses.country AS address_country,
    -- -- -- metrics,,
    CASE
        WHEN li.has_disability = 'Sim' THEN TRUE
        WHEN li.has_disability = 'Não' THEN FALSE
        ELSE FALSE
    END AS has_disability,
    -- -- dates
    DATE(workers.dt_birth) AS dt_birth,
    NOW() AS ts_load
FROM
    hr_system_workers AS workers
LEFT JOIN 
    ethnicities 
        ON workers.id_person = ethnicities.id_person
LEFT JOIN 
    legislative_info_data AS li 
        ON workers.id_person = li.id_person
LEFT JOIN 
    emails AS ew 
        ON workers.id_person = ew.id_person
        AND ew.email_type = 'W1'
LEFT JOIN 
    emails AS eh 
        ON workers.id_person = eh.id_person
        AND eh.email_type = 'H1'
LEFT JOIN 
    addresses 
        ON workers.id_person = addresses.id_person
LEFT JOIN 
    names 
        ON workers.id_person = names.id_person
LEFT JOIN 
    workers_dff AS wdff 
        ON workers.id_person = wdff.id_person
LEFT JOIN 
    phones 
        ON workers.id_person = phones.id_person
LEFT JOIN  
    religions 
        ON workers.id_person = religions.id_person
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