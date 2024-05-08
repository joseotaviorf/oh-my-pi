WITH hr_system_workers AS (
  SELECT
    id_person,
    person_number,
    birth_town,
    birth_region,
    birth_country,
    birth_country_name,
    dt_birth,
    work_relationships,
    national_identifiers,
    ethnicities,
    legislative_info,
    emails,
    addresses,
    names,
    workers_dff,
    phones,
    religions,
    external_identifiers,
    dt_effective,
    CASE
      WHEN dense_rank() OVER (ORDER BY dt_effective) = 1
        THEN 'past'
      WHEN dense_rank() OVER (ORDER BY dt_effective) = 2
        THEN 'present'
      WHEN dense_rank() OVER (ORDER BY dt_effective) = 3
        THEN 'future'
    END AS data_moment
  FROM datalake_hr_system_clean.workers
), hr_system_workers_present AS (
  SELECT *
  FROM hr_system_workers
  WHERE data_moment = 'present'
)
, external_identifiers_step1 AS (
  SELECT 
    id_person,
    explode(external_identifiers) external_identifiers
  FROM hr_system_workers_present
), external_identifiers AS (
  SELECT 
    id_person
  FROM external_identifiers_step1
  WHERE external_identifiers['ExternalIdentifierType'] = 'ID_ONDA1'
)
, work_rel_step1 AS(
  SELECT
    id_person,
    data_moment,
    dt_effective,
    explode(work_relationships) as work_relationships
  FROM hr_system_workers 
), work_rel AS (
  SELECT 
    id_person,
    data_moment,
    dt_effective,
    work_relationships['PeriodOfServiceId'] AS id_period_service,
    work_relationships['LegalEmployerName'] AS legal_employer_name,
    work_relationships['WorkerType'] AS worker_type,
    work_relationships['TerminationDate'] AS dt_termination_work_relationship,
    work_relationships['NotificationDate'] AS dt_notification,
    work_relationships['StartDate'] AS dt_start_work_relationship,
    work_relationships['assignments'] AS assignments,
    work_relationships['LegislationCode'] AS legislation_code
  FROM work_rel_step1
  WHERE work_relationships['PrimaryFlag'] = 'true'
  QUALIFY work_relationships['StartDate'] = MAX(work_relationships['StartDate']) OVER (PARTITION BY id_person, data_moment)
), assignments_step1 AS (
  SELECT 
    id_person,
    id_period_service,
    data_moment,
    explode(assignments) as assignments
  FROM work_rel
), assignments AS (
  SELECT 
    id_person,
    id_period_service,
    data_moment,
    assignments['AssignmentId'] AS id_assignment,
    assignments['AssignmentNumber'] AS assignment_number,
    assignments['AssignmentStatusType'] AS assignment_status_type,
    assignments['EffectiveStartDate'] AS dt_assignment_effective_start,
    assignments['BusinessUnitName'] AS business_unit_name,
    assignments['DepartmentId'] AS id_department,
    assignments['DepartmentName'] AS department_name,
    assignments['JobId'] AS id_job,
    assignments['JobCode'] AS job_code,
    assignments['AssignmentName'] AS assignment_name,
    assignments['AssignmentCategory'] AS assignment_category,
    assignments['ActionCode'] AS action_code,
    assignments['ReasonCode'] AS reason_code,
    assignments['ReasonName'] AS reason_name,
    assignments['GradeCode'] AS band,
    assignments['GradeLadderName'] AS band_ladder_name,
    assignments['managers'] AS managers,
    assignments['assignmentsDFF'] AS assignments_dff,
    assignments['EffectiveEndDate'] AS dt_effective_end,
    assignments['ManagerFlag'] AS manager_flag,
    assignments['representatives'] AS representatives
  FROM assignments_step1
  QUALIFY assignments['EffectiveEndDate'] = MAX(assignments['EffectiveEndDate']) OVER (PARTITION BY id_person, id_period_service, data_moment)
), managers_step1 AS (
  SELECT 
    id_person,
    id_period_service,
    id_assignment,
    data_moment,
    explode(managers) as managers
  FROM assignments
), managers AS (
  SELECT 
    id_person,
    id_period_service,
    id_assignment,
    data_moment,
    managers["ManagerType"] AS manager_type,
    managers["ManagerAssignmentId"] AS id_manager_assignment,
    managers["ManagerAssignmentNumber"] AS manager_assignment_number,
    managers["EffectiveEndDate"] AS dt_effective_end
  FROM managers_step1
  WHERE managers["ManagerType"] = 'LINE_MANAGER'
  QUALIFY managers["EffectiveEndDate"] = MAX(managers["EffectiveEndDate"]) OVER (PARTITION BY id_person, id_period_service, id_assignment, data_moment)
), assignments_dff_step1 AS (
  SELECT 
    id_person,
    id_period_service,
    id_assignment,
    data_moment,
    explode(assignments_dff) as assignments_dff
  FROM assignments
), assignments_dff AS (
  SELECT 
    id_person,
    id_period_service,
    id_assignment,
    data_moment,
    assignments_dff["dataFinalDaExperiencia1"] AS dt_experience_period_1,
    assignments_dff["dataFinalDaExperiencia2"] AS dt_experience_period_2,
    assignments_dff["EffectiveEndDate"] AS dt_effective_end,
    assignments_dff["funcionarioMarcaPonto"] AS has_clock_in,
    assignments_dff["trilha"] AS trilha,
    assignments_dff["targetPlr"] AS target_plr,
    assignments_dff['marcaProduto'] AS brand
  FROM assignments_dff_step1
  QUALIFY assignments_dff["EffectiveEndDate"] = MAX(assignments_dff["EffectiveEndDate"]) OVER (PARTITION BY id_person, id_period_service, id_assignment, data_moment)
), representatives_step1 AS (
  SELECT 
    id_person,
    id_period_service,
    id_assignment,
    data_moment,
    explode(representatives) as representatives
  FROM assignments
), representatives AS (
  SELECT 
    id_person,
    id_period_service,
    id_assignment,
    data_moment,
    representatives['PersonId'] AS id_person_hrbp,
    representatives['AssignmentNumber'] AS assignment_number_hrbp,
    representatives['ResponsibilityName'] AS responsibility_name_hrbp
  FROM representatives_step1
  WHERE representatives['ResponsibilityType'] = 'BPs'
  QUALIFY representatives['FromDate'] = MAX(representatives['FromDate']) OVER (PARTITION BY id_assignment, data_moment)
)
, work_relationship_data AS (
  SELECT 
    work_rel.id_person,
    work_rel.id_period_service,
    work_rel.legal_employer_name,
    work_rel.worker_type,
    work_rel.dt_termination_work_relationship,
    work_rel.dt_notification,
    work_rel.dt_start_work_relationship,
    work_rel.legislation_code,
    work_rel.data_moment,
    work_rel.dt_effective, 
    assignments.id_assignment,
    assignments.assignment_number,
    assignments.assignment_status_type,
    assignments.dt_assignment_effective_start,
    assignments.business_unit_name,
    assignments.id_department,
    assignments.department_name,
    assignments.id_job,
    assignments.job_code,
    assignments.assignment_name,
    assignments.assignment_category,
    assignments.action_code,
    assignments.reason_code,
    assignments.reason_name,
    assignments.band,
    assignments.band_ladder_name,
    assignments.manager_flag,
    managers.id_manager_assignment,
    managers.manager_assignment_number,
    assignments_dff.dt_experience_period_1,
    assignments_dff.dt_experience_period_2,
    assignments_dff.has_clock_in,
    assignments_dff.trilha,
    assignments_dff.target_plr,
    assignments_dff.brand,
    representatives.id_person_hrbp,
    representatives.assignment_number_hrbp,
    representatives.responsibility_name_hrbp
  FROM work_rel
  LEFT JOIN 
    assignments
      ON work_rel.id_person = assignments.id_person
      AND work_rel.id_period_service = assignments.id_period_service
      AND work_rel.data_moment = assignments.data_moment
  LEFT JOIN 
    managers
      ON work_rel.id_person = managers.id_person
      AND work_rel.id_period_service = managers.id_period_service
      AND assignments.id_assignment = managers.id_assignment
      AND work_rel.data_moment = managers.data_moment
  LEFT JOIN 
    assignments_dff
      ON work_rel.id_person = assignments_dff.id_person
      AND work_rel.id_period_service = assignments_dff.id_period_service
      AND assignments.id_assignment = assignments_dff.id_assignment
      AND work_rel.data_moment = assignments_dff.data_moment
  LEFT JOIN 
    representatives
      ON work_rel.id_person = representatives.id_person
      AND work_rel.id_period_service = representatives.id_period_service
      AND assignments.id_assignment = representatives.id_assignment
      AND work_rel.data_moment = representatives.data_moment
), national_identifiers_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(national_identifiers) national_identifiers
  FROM hr_system_workers_present
), national_identifiers_step2 AS (
  SELECT 
    id_person,
    person_number,
    national_identifiers['NationalIdentifierId'] AS id_national_identifier,
    national_identifiers['NationalIdentifierNumber'] AS national_identifier_number,
    national_identifiers['NationalIdentifierType'] AS national_identifier_type,
    national_identifiers['nationalIdentifiersDFF'] AS national_identifiers_dff
  FROM national_identifiers_step1
), national_identifiers_dff_step1 AS (
  SELECT 
    id_person,
    person_number,
    id_national_identifier,
    explode(national_identifiers_dff) as national_identifiers_dff
  FROM national_identifiers_step2
), national_identifiers_dff AS (
  SELECT 
    id_person,
    person_number,
    id_national_identifier,
    national_identifiers_dff["ufDeEmissao"] AS issuing_state,
    national_identifiers_dff["orgaoDeEmissao"] AS issuing_authority
  FROM national_identifiers_dff_step1
), ethnicities_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(ethnicities) ethnicities
  FROM hr_system_workers_present
), ethnicities AS (
  SELECT 
    id_person,
    person_number,
    ethnicities['EthnicityId'] AS id_ethnicity,
    ethnicities['Ethnicity'] AS ethnicity,
    ethnicities['LegislationCode'] AS legislation_code
  FROM ethnicities_step1
  WHERE ethnicities['PrimaryFlag'] = 'true'
), legislative_info_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(legislative_info) legislative_info
  FROM hr_system_workers_present
), legislative_info AS (
  SELECT 
    id_person,
    person_number,
    legislative_info['PersonLegislativeId'] AS id_person_legislative,
    legislative_info['MaritalStatus'] AS marital_status,
    legislative_info['Gender'] AS gender,
    legislative_info['HighestEducationLevel'] AS highest_education_level,
    legislative_info['legislativeInfoDFF'] AS legislative_info_dff,
    legislative_info['legislativeInfoDDF'] AS legislative_info_ddf,
    legislative_info['LegislationCode'] AS legislation_code
  FROM legislative_info_step1
), legislative_info_ddf_step1 AS (
SELECT 
    id_person,
    person_number,
    id_person_legislative,
    explode(legislative_info_ddf) AS legislative_info_ddf
FROM legislative_info
), legislative_info_ddf AS (
  SELECT 
    id_person,
    person_number,
    id_person_legislative,
    legislative_info_ddf["ctpsNumber"] AS ctps_number,
    legislative_info_ddf["ctpsSeries"] AS ctps_series,
    legislative_info_ddf["issuingState"] AS issuing_state_ctps
  FROM legislative_info_ddf_step1
), legislative_info_dff_step1 AS (
  SELECT 
    id_person,
    person_number,
    id_person_legislative,
    explode(legislative_info_dff) AS legislative_info_dff
  FROM legislative_info
), legislative_info_dff AS (
  SELECT 
    id_person,
    person_number,
    id_person_legislative,
    legislative_info_dff["numeroDoTituloDeEleitor"] AS vote_registration_number,
    legislative_info_dff["zonaEleitoralDoTitulo"] AS electoral_zone,
    legislative_info_dff["secaoEleitoralDoTitulo"] AS polling_station,
    legislative_info_dff["possuiAlgumaDeficiencia"] AS has_disability,
    legislative_info_dff["orientacaoSexual"] AS sexual_orientation,
    legislative_info_dff["genero"] AS genero,
    legislative_info_dff["neurodiversidade"] AS neurodiversidade,
    legislative_info_dff["__FLEX_Context"] AS nacionalidade,
    legislative_info_dff["desejaReceberAdiantamentoSalar"] AS has_salary_advance
  FROM legislative_info_dff_step1
), legislative_info_data AS (
  SELECT 
    li.id_person,
    li.person_number,
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
  FROM legislative_info AS li
  LEFT JOIN 
    legislative_info_ddf AS liddf
      ON li.id_person = liddf.id_person
      AND li.id_person_legislative = liddf.id_person_legislative
  LEFT JOIN 
    legislative_info_dff as lidff
      ON li.id_person = lidff.id_person
      AND li.id_person_legislative = lidff.id_person_legislative
), emails_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(emails) emails
  FROM hr_system_workers_present
), emails AS (
  SELECT 
    id_person,
    person_number,
    emails['EmailAddressId'] AS id_email_address,
    emails['EmailType'] AS email_type,
    emails['EmailAddress'] AS email_address,
    emails['PrimaryFlag'] AS primary_flag
  FROM emails_step1
  WHERE emails['ToDate'] IS NULL OR emails['ToDate'] = '4712-12-31'
  QUALIFY emails['LastUpdateDate'] = MAX(emails['LastUpdateDate']) OVER (PARTITION BY id_person, emails['EmailType'])
), addresses_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(addresses) addresses
  FROM hr_system_workers_present
), addresses AS (
  SELECT 
    id_person,
    person_number,
    addresses['AddressId'] AS id_address,
    addresses['AddlAddressAttribute3'] AS addl_address_attribute_3,
    addresses['AddressLine1'] AS address_line_1,
    addresses['AddressLine2'] AS address_line_2,
    addresses['AddressLine3'] AS address_line_3,
    addresses['AddressLine4'] AS address_line_4,
    addresses['PostalCode'] AS postal_code,
    addresses['TownOrCity'] AS town_or_city,
    addresses['Region2'] AS region_2,
    addresses['Country'] AS country
  FROM addresses_step1
  WHERE addresses['PrimaryFlag'] = 'true'
), names_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(names) names
  FROM hr_system_workers_present
), names AS (
  SELECT 
    id_person,
    person_number,
    names["FirstName"] AS first_name,
    names["FullName"] AS full_name,
    names["LastName"] AS last_name,
    names["NameInformation15"] AS name_information_15,
    names["NameInformation16"] AS name_information_16
  FROM names_step1
), workers_dff_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(workers_dff) workers_dff
  FROM hr_system_workers_present
), workers_dff AS (
  SELECT 
    id_person,
    person_number,
    workers_dff["nomeDaMae"] AS mother_name,
    workers_dff["nomeDoPai"] AS father_name
  FROM workers_dff_step1
), phones_step1 AS (
  SELECT 
    id_person,
    person_number,
    explode(phones) AS phones
  FROM hr_system_workers_present
), phones AS (
  SELECT 
    id_person,
    person_number,
    phones['PhoneId'] AS id_phone,
    phones['CountryCodeNumber'] AS country_code_number,
    phones['AreaCode'] AS area_code,
    phones['PhoneNumber'] AS phone_number
  FROM phones_step1
  WHERE phones['PrimaryFlag'] = 'true'
), managers_data AS (
  SELECT
    wr.id_person,
    wr.id_period_service,
    wr.id_assignment,
    wr_manager.id_person AS id_person_manager,
    wr.manager_assignment_number,
    wr.id_manager_assignment,
    w.person_number AS person_number_manager,
    names.first_name AS first_name_manager,
    names.full_name AS full_name_manager,
    names.last_name AS last_name_manager,
    names.name_information_15 AS name_information_15_manager,
    names.name_information_16 AS name_information_16_manager,
    emails.email_address as email_manager,
    wr.data_moment,
    wr.dt_effective
  FROM work_relationship_data as wr
  LEFT JOIN 
    work_relationship_data as wr_manager
      ON wr.id_manager_assignment = wr_manager.id_assignment
      AND wr.data_moment = wr_manager.data_moment
  LEFT JOIN 
    hr_system_workers AS w
      ON wr_manager.id_person = w.id_person
      AND wr_manager.data_moment = w.data_moment
  LEFT JOIN 
    names
      ON wr_manager.id_person = names.id_person
  LEFT JOIN 
    emails
      ON wr_manager.id_person = emails.id_person
      AND emails.email_type = 'W1'
      AND emails.primary_flag = 'true'
), religions_step1 AS (
  SELECT 
    id_person,
    person_number,
    explode(religions) religions
  FROM hr_system_workers_present
), religions AS (
  SELECT 
    id_person,
    person_number,
    religions["Religion"] as religion,
    religions['LegislationCode'] AS legislation_code
  FROM religions_step1
  WHERE religions["PrimaryFlag"] = 'true'
), salaries AS (
  SELECT 
    id_salary,
    id_assignment,
    salary_amount,
    currency_code
  FROM datalake_hr_system_clean.salaries
  QUALIFY dt_to = MAX(dt_to) OVER (PARTITION BY assignment_number)
  )
SELECT
  --  ids
  workers.id_person,
  --  non-ids,
  work_rel.id_period_service AS id_period_of_service,
  work_rel.id_assignment,
  work_rel.id_department,
  work_rel.id_job,
  salaries.id_salary,
  COALESCE(managers_data.id_person_manager, md_past.id_person_manager) AS id_person_manager,
  ew.id_email_address AS id_work_email,
  eh.id_email_address AS id_personal_email,
  phones.id_phone,
  addresses.id_address,
  COALESCE(managers_data.id_manager_assignment, md_past.id_manager_assignment) AS id_assignment_manager,
  ethnicities.id_ethnicity,
  work_rel.id_person_hrbp,
  workers.person_number,
  work_rel.assignment_number,
  -- -- non metric
  -- -- name information,
  names.first_name,
  names.last_name,
  names.full_name,
  names.name_information_15 AS first_social_name,
  names.name_information_16 AS last_social_name,
  -- -- assignment info,
  CASE
    WHEN work_rel.dt_termination_work_relationship is not null
      THEN al.action_name
  END AS dismissal_type,
  work_rel.assignment_name,
  work_rel.worker_type,
  work_rel.legal_employer_name,
  work_rel.business_unit_name,
  work_rel.brand,
  COALESCE(work_rel.assignment_status_type, 'PENDING') AS assignment_status_type,
  work_rel.department_name,
  work_rel.job_code,
  work_rel.assignment_category,
  work_rel.action_code,
  work_rel.reason_code,
  arl.action_reason AS reason_code_description,
  work_rel.band,
  work_rel.band_ladder_name,
  work_rel.trilha AS track,
  orgs.sub_directory AS sub_board,
  orgs.directory AS board,
  orgs.vice_presidency,
  orgs.vertical,
  orgs.business,
  orgs.product,
  salaries.currency_code,
  work_rel.legislation_code,
  work_rel.assignment_number_hrbp,
  work_rel.responsibility_name_hrbp,
  -- -- -- Managers,
  COALESCE(managers_data.manager_assignment_number, md_past.manager_assignment_number) AS manager_assignment_number,
  COALESCE(managers_data.person_number_manager, md_past.person_number_manager)  AS manager_person_number,
  COALESCE(managers_data.full_name_manager, md_past.full_name_manager) AS manager_full_name,
  COALESCE(managers_data.email_manager, md_past.email_manager) AS email_manager,
  -- -- birth info,
  workers.birth_town,
  workers.birth_region,
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
  ethnicities.ethnicity,
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
    ELSE NULL
  END  AS ethnicity_description,
  li.marital_status,
  CASE 
    WHEN marital_status = 'C' THEN 'Casado(a)'
    WHEN marital_status = 'D' THEN 'Divorciado(a)'
    WHEN marital_status = 'M' THEN 'União Estável'
    WHEN marital_status = 'O' THEN 'Outros'
    WHEN marital_status = 'Q' THEN 'Desquitado(a) / Separado(a)'
    WHEN marital_status = 'S' THEN 'Solteiro'
    WHEN marital_status = 'V' THEN 'Viúvo(a)'
    WHEN marital_status = 'N' THEN 'Não informado'
    WHEN marital_status = 'ORA_HRX_SEP' THEN 'Separado(a)'
    ELSE 'Unknown Marital Status'
  END AS marital_status_description,
  li.gender,
  li.sexual_orientation,
  li.genero AS gender_identity,
  li.neurodiversidade AS neurodiversity,
  religions.religion,
  CASE
    WHEN religions.religion='Agnosticismo' THEN 'Agnosticismo'
    WHEN religions.religion='Ateísmo' THEN 'Ateísmo'
    WHEN religions.religion='Candomblé' THEN 'Candomblé'
    WHEN religions.religion='Mórmon' THEN 'Mórmon'
    WHEN religions.religion='ORA_HRX_CATHOLICISM' THEN 'Catolicismo'
    WHEN religions.religion='OTHER' THEN 'Outra'
    WHEN religions.religion='Umbanda' THEN 'Umbanda'
    WHEN religions.religion='CHRISTIAN' THEN LOWER(religions.religion)
    WHEN religions.religion='NONE' THEN NULL
    ELSE religions.religion
  END AS religion_name,
  li.highest_education_level AS highest_education_level_code,
  CASE  
    WHEN li.highest_education_level = 10 THEN 'Analfabeto, inclusive o que, embora tenha recebido instrução, não se alfabetizou'
    WHEN li.highest_education_level = 20 THEN 'Até o 5º ano incompleto do Ensino Fundamental (antiga 4ª série) ou que se tenha alfabetizado sem ter   frequentado escola regular'
    WHEN li.highest_education_level = 25 THEN '5º ano completo do Ensino Fundamental'
    WHEN li.highest_education_level = 30 THEN 'Do 6º ao 9º ano do Ensino Fundamental incompleto (antiga 5ª à 8ª série)'
    WHEN li.highest_education_level = 35 THEN 'Ensino Fundamental completo'
    WHEN li.highest_education_level = 40 THEN 'Ensino Médio incompleto'
    WHEN li.highest_education_level = 45 THEN 'Ensino Médio completo'
    WHEN li.highest_education_level = 807 THEN 'Técnico incompleto'
    WHEN li.highest_education_level = 803 THEN 'Tecnólogo incompleto'
    WHEN li.highest_education_level = 809 THEN 'Técnico completo'
    WHEN li.highest_education_level = 805 THEN 'Tecnólogo completo'
    WHEN li.highest_education_level = 50 THEN 'Educação Superior incompleta'
    WHEN li.highest_education_level = 55 THEN 'Educação Superior completa'
    WHEN li.highest_education_level = 801 THEN 'Pós-graduação incompleta'
    WHEN li.highest_education_level = 85 THEN 'Pós-graduação completa'
    WHEN li.highest_education_level = 800 THEN 'Mestrado incompleto'
    WHEN li.highest_education_level = 65 THEN 'Mestrado completo'
    WHEN li.highest_education_level = 13 THEN 'Doutorado incompleto'
    WHEN li.highest_education_level = 75 THEN 'Doutorado completo'
    ELSE NULL
  END as highest_education_level_name,
  -- -- -- contacts,
  ew.email_address as work_email,
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
  boolean(work_rel.manager_flag) AS is_manager,
  CASE 
    WHEN work_rel.has_clock_in = 1
      THEN TRUE
    WHEN work_rel.has_clock_in = 0
      THEN FALSE
    ELSE NULL
  END AS has_clock_in,
  CASE 
    WHEN li.has_disability = 'Sim'
      THEN TRUE
    WHEN li.has_disability = 'Não'
      THEN FALSE
    ELSE NULL 
  END AS has_disability,
  CASE 
    WHEN has_salary_advance = 'S'
      THEN TRUE
    WHEN has_salary_advance = 'N'
      THEN FALSE
    ELSE NULL
  END AS has_salary_advance,
  salaries.salary_amount,
  FLOAT(work_rel.target_plr) AS target_plr,
  -- -- dates
  DATE(workers.dt_birth) AS dt_birth,
  DATE(work_rel.dt_termination_work_relationship) AS dt_termination_work_relationship,
  DATE(work_rel.dt_start_work_relationship) AS dt_start_work_relationship,
  DATE(work_rel.dt_notification) AS dt_notification,
  DATE(work_rel.dt_assignment_effective_start) AS dt_assignment_effective_start,
  DATE(work_rel.dt_experience_period_1) AS dt_experience_period_1,
  DATE(work_rel.dt_experience_period_2) AS dt_experience_period_2,
  NOW() AS ts_load
FROM hr_system_workers_present as workers
JOIN 
  work_relationship_data as work_rel
    ON workers.id_person = work_rel.id_person
    AND workers.data_moment = work_rel.data_moment
LEFT JOIN 
  salaries
    ON work_rel.id_assignment = salaries.id_assignment
LEFT JOIN 
  ethnicities
    ON workers.id_person = ethnicities.id_person
    AND work_rel.legislation_code = ethnicities.legislation_code
LEFT JOIN 
  legislative_info_data AS li
    ON workers.id_person = li.id_person
    AND work_rel.legislation_code = li.legislation_code
LEFT JOIN 
  emails as ew
    ON workers.id_person = ew.id_person
    AND ew.email_type = 'W1'
LEFT JOIN 
  emails as eh
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
  managers_data
    ON workers.id_person = managers_data.id_person
    AND work_rel.id_period_service = managers_data.id_period_service
    AND work_rel.id_assignment = managers_data.id_assignment
    AND workers.data_moment = managers_data.data_moment
LEFT JOIN 
  religions 
    ON workers.id_person = religions.id_person
    AND work_rel.legislation_code = religions.legislation_code
LEFT JOIN 
  datalake_hr_system_clean.organizations as orgs
    ON work_rel.id_department = orgs.id_organization
LEFT JOIN 
  datalake_hr_system_clean.action_reasons_lov arl
    ON work_rel.reason_code = arl.action_reason_code
LEFT JOIN 
  external_identifiers ei 
    ON workers.id_person = ei.id_person
LEFT JOIN 
  national_identifiers_step2  ni2_cpf
    ON workers.id_person = ni2_cpf.id_person
    AND ni2_cpf.national_identifier_type = 'CPF'
LEFT JOIN 
  national_identifiers_step2  ni2_rg
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
LEFT JOIN managers_data AS md_past
    ON workers.id_person = md_past.id_person
    AND work_rel.id_period_service = md_past.id_period_service
    AND work_rel.id_assignment = md_past.id_assignment
    AND workers.data_moment = 'present'
    AND md_past.data_moment = 'past'
    AND DATE(work_rel.dt_termination_work_relationship) >= to_date(md_past.dt_effective, 'yyyyMMdd')
    AND DATE(work_rel.dt_termination_work_relationship) < to_date(workers.dt_effective, 'yyyyMMdd')
LEFT JOIN 
  work_relationship_data as work_rel_future
    ON workers.id_person = work_rel_future.id_person
    AND workers.data_moment = 'present'
    AND work_rel_future.data_moment = 'future'
    AND DATE(work_rel.dt_termination_work_relationship) >= to_date(workers.dt_effective, 'yyyyMMdd')
LEFT JOIN 
  datalake_hr_system_clean.actions_lov AS al
    ON COALESCE(work_rel_future.action_code, work_rel.action_code) = al.action_code
WHERE ei.id_person is null
