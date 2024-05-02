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
    external_identifiers
  FROM datalake_hr_system_clean.workers
), external_identifiers_step1 AS (
  SELECT 
    id_person,
    explode(external_identifiers) external_identifiers
  FROM hr_system_workers
), external_identifiers AS (
  SELECT 
    id_person
  FROM external_identifiers_step1
  WHERE external_identifiers['ExternalIdentifierType'] = 'ID_ONDA1'
)
, work_rel_step1 AS(
  SELECT
    id_person,
    explode(work_relationships) as work_relationships
  FROM hr_system_workers 
), work_rel AS (
  SELECT 
    id_person,
    work_relationships['PeriodOfServiceId'] AS PeriodOfServiceId,
    work_relationships['LegalEmployerName'] AS LegalEmployerName,
    work_relationships['WorkerType'] AS WorkerType,
    work_relationships['TerminationDate'] AS TerminationDate,
    work_relationships['NotificationDate'] AS NotificationDate,
    work_relationships['StartDate'] AS StartDate,
    work_relationships['assignments'] AS assignments,
    work_relationships['LegislationCode'] AS LegislationCode
  FROM work_rel_step1
  WHERE work_relationships['PrimaryFlag'] = 'true'
  QUALIFY work_relationships['StartDate'] = MAX(work_relationships['StartDate']) OVER (PARTITION BY id_person)
), assignments_step1 AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    explode(assignments) as assignments
  FROM work_rel
), assignments AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    assignments['AssignmentId'] AS AssignmentId,
    assignments['AssignmentNumber'] AS AssignmentNumber,
    assignments['AssignmentStatusType'] AS AssignmentStatusType,
    assignments['EffectiveStartDate'] AS EffectiveStartDate,
    assignments['BusinessUnitName'] AS BusinessUnitName,
    assignments['DepartmentId'] AS DepartmentId,
    assignments['DepartmentName'] AS DepartmentName,
    assignments['JobId'] AS JobId,
    assignments['JobCode'] AS JobCode,
    assignments['AssignmentName'] AS AssignmentName,
    assignments['AssignmentCategory'] AS AssignmentCategory,
    assignments['ActionCode'] AS ActionCode,
    assignments['ReasonCode'] AS ReasonCode,
    assignments['ReasonName'] AS ReasonName,
    assignments['GradeCode'] AS GradeCode,
    assignments['GradeLadderName'] AS GradeLadderName,
    assignments['managers'] AS managers,
    assignments['assignmentsDFF'] AS assignmentsDFF,
    assignments['EffectiveEndDate'] AS EffectiveEndDate,
    assignments['ManagerFlag'] AS ManagerFlag,
    assignments['representatives'] AS representatives
  FROM assignments_step1
  QUALIFY assignments['EffectiveEndDate'] = MAX(assignments['EffectiveEndDate']) OVER (PARTITION BY id_person, PeriodOfServiceId)
), managers_step1 AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    AssignmentId,
    explode(managers) as managers
  FROM assignments
), managers AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    AssignmentId,
    managers["ManagerType"] AS ManagerType,
    managers["ManagerAssignmentId"] AS ManagerAssignmentId,
    managers["ManagerAssignmentNumber"] AS ManagerAssignmentNumber,
    managers["EffectiveEndDate"] AS EffectiveEndDate
  FROM managers_step1
  WHERE managers["ManagerType"] = 'LINE_MANAGER'
  QUALIFY managers["EffectiveEndDate"] = MAX(managers["EffectiveEndDate"]) OVER (PARTITION BY id_person, PeriodOfServiceId, AssignmentId)
), assignmentsDFF_step1 AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    AssignmentId,
    explode(assignmentsDFF) as assignmentsDFF
  FROM assignments
), assignmentsDFF AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    AssignmentId,
    assignmentsDFF["dataFinalDaExperiencia1"] AS dataFinalDaExperiencia1,
    assignmentsDFF["dataFinalDaExperiencia2"] AS dataFinalDaExperiencia2,
    assignmentsDFF["EffectiveEndDate"] AS EffectiveEndDate,
    assignmentsDFF["funcionarioMarcaPonto"] AS funcionarioMarcaPonto,
    assignmentsDFF["trilha"] AS trilha,
    assignmentsDFF["targetPlr"] AS targetPlr,
    assignmentsDFF['marcaProduto'] AS marcaProduto
  FROM assignmentsDFF_step1
  QUALIFY assignmentsDFF["EffectiveEndDate"] = MAX(assignmentsDFF["EffectiveEndDate"]) OVER (PARTITION BY id_person, PeriodOfServiceId, AssignmentId)
), representatives_step1 AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    AssignmentId,
    explode(representatives) as representatives
  FROM assignments
), representatives AS (
  SELECT 
    id_person,
    PeriodOfServiceId,
    AssignmentId,
    representatives['PersonId'] AS id_person_hrbp,
    representatives['AssignmentNumber'] AS assignment_number_hrbp,
    representatives['ResponsibilityName'] AS responsibility_name_hrbp
  FROM representatives_step1
  WHERE representatives['ResponsibilityType'] = 'BPs'
  QUALIFY representatives['FromDate'] = MAX(representatives['FromDate']) OVER (PARTITION BY AssignmentId)
)
, work_relationship_data AS (
  SELECT 
    work_rel.id_person,
    work_rel.PeriodOfServiceId,
    work_rel.LegalEmployerName,
    work_rel.WorkerType,
    work_rel.TerminationDate,
    work_rel.NotificationDate,
    work_rel.StartDate,
    work_rel.LegislationCode,
    assignments.AssignmentId,
    assignments.AssignmentNumber,
    assignments.AssignmentStatusType,
    assignments.EffectiveStartDate,
    assignments.BusinessUnitName,
    assignments.DepartmentId,
    assignments.DepartmentName,
    assignments.JobId,
    assignments.JobCode,
    assignments.AssignmentName,
    assignments.AssignmentCategory,
    assignments.ActionCode,
    assignments.ReasonCode,
    assignments.ReasonName,
    assignments.GradeCode,
    assignments.GradeLadderName,
    assignments.ManagerFlag,
    managers.ManagerAssignmentId,
    managers.ManagerAssignmentNumber,
    assignmentsDFF.dataFinalDaExperiencia1,
    assignmentsDFF.dataFinalDaExperiencia2,
    assignmentsDFF.funcionarioMarcaPonto,
    assignmentsDFF.trilha,
    assignmentsDFF.targetPlr,
    assignmentsDFF.marcaProduto,
    representatives.id_person_hrbp,
    representatives.assignment_number_hrbp,
    representatives.responsibility_name_hrbp
  FROM work_rel
  LEFT JOIN 
    assignments
      ON work_rel.id_person = assignments.id_person
      AND work_rel.PeriodOfServiceId = assignments.PeriodOfServiceId
  LEFT JOIN 
    managers
      ON work_rel.id_person = managers.id_person
      AND work_rel.PeriodOfServiceId = managers.PeriodOfServiceId
      AND assignments.AssignmentId = managers.AssignmentId
  LEFT JOIN 
    assignmentsDFF
      ON work_rel.id_person = assignmentsDFF.id_person
      AND work_rel.PeriodOfServiceId = assignmentsDFF.PeriodOfServiceId
      AND assignments.AssignmentId = assignmentsDFF.AssignmentId
  LEFT JOIN 
    representatives
      ON work_rel.id_person = representatives.id_person
      AND work_rel.PeriodOfServiceId = representatives.PeriodOfServiceId
      AND assignments.AssignmentId = representatives.AssignmentId
), national_identifiers_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(national_identifiers) national_identifiers
  FROM hr_system_workers
), national_identifiers_step2 AS (
  SELECT 
    id_person,
    person_number,
    national_identifiers['NationalIdentifierId'] AS NationalIdentifierId,
    national_identifiers['NationalIdentifierNumber'] AS NationalIdentifierNumber,
    national_identifiers['NationalIdentifierType'] AS NationalIdentifierType,
    national_identifiers['nationalIdentifiersDFF'] AS nationalIdentifiersDFF
  FROM national_identifiers_step1
), nationalIdentifiersDFF_step1 AS (
  SELECT 
    id_person,
    person_number,
    NationalIdentifierId,
    explode(nationalIdentifiersDFF) as nationalIdentifiersDFF
  FROM national_identifiers_step2
), nationalIdentifiersDFF AS (
  SELECT 
    id_person,
    person_number,
    NationalIdentifierId,
    nationalIdentifiersDFF["ufDeEmissao"] AS ufDeEmissao,
    nationalIdentifiersDFF["orgaoDeEmissao"] AS orgaoDeEmissao
  FROM nationalIdentifiersDFF_step1
), ethnicities_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(ethnicities) ethnicities
  FROM hr_system_workers
), ethnicities AS (
  SELECT 
    id_person,
    person_number,
    ethnicities['EthnicityId'] AS EthnicityId,
    ethnicities['Ethnicity'] AS Ethnicity,
    ethnicities['LegislationCode'] AS LegislationCode
  FROM ethnicities_step1
  WHERE ethnicities['PrimaryFlag'] = 'true'
), legislative_info_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(legislative_info) legislative_info
  FROM hr_system_workers
), legislative_info AS (
  SELECT 
    id_person,
    person_number,
    legislative_info['PersonLegislativeId'] AS PersonLegislativeId,
    legislative_info['MaritalStatus'] AS MaritalStatus,
    legislative_info['Gender'] AS Gender,
    legislative_info['HighestEducationLevel'] AS HighestEducationLevel,
    legislative_info['legislativeInfoDFF'] AS legislativeInfoDFF,
    legislative_info['legislativeInfoDDF'] AS legislativeInfoDDF,
    legislative_info['LegislationCode'] AS LegislationCode
  FROM legislative_info_step1
), legislativeInfoDDF_step1 AS (
SELECT 
    id_person,
    person_number,
    PersonLegislativeId,
    explode(legislativeInfoDDF) AS legislativeInfoDDF
FROM legislative_info
), legislativeInfoDDF AS (
  SELECT 
    id_person,
    person_number,
    PersonLegislativeId,
    legislativeInfoDDF["ctpsNumber"] AS ctpsNumber,
    legislativeInfoDDF["ctpsSeries"] AS ctpsSeries,
    legislativeInfoDDF["issuingState"] AS issuingState
  FROM legislativeInfoDDF_step1
), legislativeInfoDFF_step1 AS (
  SELECT 
    id_person,
    person_number,
    PersonLegislativeId,
    explode(legislativeInfoDFF) AS legislativeInfoDFF
  FROM legislative_info
), legislativeInfoDFF AS (
  SELECT 
    id_person,
    person_number,
    PersonLegislativeId,
    legislativeInfoDFF["numeroDoTituloDeEleitor"] AS numeroDoTituloDeEleitor,
    legislativeInfoDFF["zonaEleitoralDoTitulo"] AS zonaEleitoralDoTitulo,
    legislativeInfoDFF["secaoEleitoralDoTitulo"] AS secaoEleitoralDoTitulo,
    legislativeInfoDFF["possuiAlgumaDeficiencia"] AS possuiAlgumaDeficiencia,
    legislativeInfoDFF["orientacaoSexual"] AS orientacaoSexual,
    legislativeInfoDFF["genero"] AS genero,
    legislativeInfoDFF["neurodiversidade"] AS neurodiversidade,
    legislativeInfoDFF["__FLEX_Context"] AS nacionalidade,
    legislativeInfoDFF["desejaReceberAdiantamentoSalar"] AS desejaReceberAdiantamentoSalar
  FROM legislativeInfoDFF_step1
), legislative_info_data AS (
  SELECT 
    li.id_person,
    li.person_number,
    li.MaritalStatus,
    li.Gender,
    li.HighestEducationLevel,
    li.LegislationCode,
    liddf.ctpsNumber,
    liddf.ctpsSeries,
    liddf.issuingState,
    lidff.numeroDoTituloDeEleitor,
    lidff.zonaEleitoralDoTitulo,
    lidff.secaoEleitoralDoTitulo,
    lidff.possuiAlgumaDeficiencia,
    lidff.orientacaoSexual,
    lidff.genero,
    lidff.neurodiversidade,
    lidff.nacionalidade,
    lidff.desejaReceberAdiantamentoSalar
  FROM legislative_info AS li
  LEFT JOIN 
    legislativeInfoDDF AS liddf
      ON li.id_person = liddf.id_person
      AND li.PersonLegislativeId = liddf.PersonLegislativeId
  LEFT JOIN 
    legislativeInfoDFF as lidff
      ON li.id_person = lidff.id_person
      AND li.PersonLegislativeId = lidff.PersonLegislativeId
), emails_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(emails) emails
  FROM hr_system_workers
), emails AS (
  SELECT 
    id_person,
    person_number,
    emails['EmailAddressId'] AS EmailAddressId,
    emails['EmailType'] AS EmailType,
    emails['EmailAddress'] AS EmailAddress,
    emails['PrimaryFlag'] AS PrimaryFlag
  FROM emails_step1
  WHERE emails['ToDate'] IS NULL OR emails['ToDate'] = '4712-12-31'
  QUALIFY emails['LastUpdateDate'] = MAX(emails['LastUpdateDate']) OVER (PARTITION BY id_person, emails['EmailType'])
), addresses_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(addresses) addresses
  FROM hr_system_workers
), addresses AS (
  SELECT 
    id_person,
    person_number,
    addresses['AddressId'] AS AddressId,
    addresses['AddlAddressAttribute3'] AS AddlAddressAttribute3,
    addresses['AddressLine1'] AS AddressLine1,
    addresses['AddressLine2'] AS AddressLine2,
    addresses['AddressLine3'] AS AddressLine3,
    addresses['AddressLine4'] AS AddressLine4,
    addresses['PostalCode'] AS PostalCode,
    addresses['TownOrCity'] AS TownOrCity,
    addresses['Region2'] AS Region2,
    addresses['Country'] AS Country
  FROM addresses_step1
  WHERE addresses['PrimaryFlag'] = 'true'
), names_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(names) names
  FROM hr_system_workers
), names AS (
  SELECT 
    id_person,
    person_number,
    names["FirstName"] AS FirstName,
    names["FullName"] AS FullName,
    names["LastName"] AS LastName,
    names["NameInformation15"] AS NameInformation15,
    names["NameInformation16"] AS NameInformation16
  FROM names_step1
), workers_dff_step1 AS (
  SELECT  
    id_person,
    person_number,
    explode(workers_dff) workers_dff
  FROM hr_system_workers
), workers_dff AS (
  SELECT 
    id_person,
    person_number,
    workers_dff["nomeDaMae"] AS nomeDaMae,
    workers_dff["nomeDoPai"] AS nomeDoPai
  FROM workers_dff_step1
), phones_step1 AS (
  SELECT 
    id_person,
    person_number,
    explode(phones) AS phones
  FROM hr_system_workers
), phones AS (
  SELECT 
    id_person,
    person_number,
    phones['PhoneId'] AS PhoneId,
    phones['CountryCodeNumber'] AS CountryCodeNumber,
    phones['AreaCode'] AS AreaCode,
    phones['PhoneNumber'] AS PhoneNumber
  FROM phones_step1
  WHERE phones['PrimaryFlag'] = 'true'
), managers_data AS (
  SELECT
    wr.id_person,
    wr.PeriodOfServiceId,
    wr.AssignmentId,
    wr_manager.id_person AS id_person_manager,
    w.person_number AS person_number_manager,
    names.FirstName AS FirstNameManager,
    names.FullName AS FullNameManager,
    names.LastName AS LastNameManager,
    names.NameInformation15 AS NameInformation15Manager,
    names.NameInformation16 AS NameInformation16Manager,
    emails.EmailAddress as EmailManager
  FROM work_relationship_data as wr
  LEFT JOIN 
    work_relationship_data as wr_manager
      ON wr.ManagerAssignmentId = wr_manager.AssignmentId
  LEFT JOIN 
    hr_system_workers AS w
      ON wr_manager.id_person = w.id_person
  LEFT JOIN 
    names
      ON wr_manager.id_person = names.id_person
  LEFT JOIN 
    emails
      ON wr_manager.id_person = emails.id_person
      AND emails.EmailType = 'W1'
      AND emails.PrimaryFlag = 'true'
), religions_step1 AS (
  SELECT 
    id_person,
    person_number,
    explode(religions) religions
  FROM hr_system_workers
), religions AS (
  SELECT 
    id_person,
    person_number,
    religions["Religion"] as Religion,
    religions['LegislationCode'] AS LegislationCode
  FROM religions_step1
  WHERE religions["PrimaryFlag"] = 'true'
), organization_dff_step1 AS (
  SELECT 
    id_organization,
    explode(organization_dff) AS organization_dff
  FROM datalake_hr_system_clean.organizations
), organization_dff AS (
  SELECT 
    id_organization,
    organization_dff['subDiretoria'] AS subDiretoria,
    organization_dff['diretoria'] AS diretoria,
    organization_dff['vicePresidencia'] AS vicePresidencia,
    organization_dff['vertical'] AS vertical,
    organization_dff['business'] AS business,
    organization_dff['product'] AS product
  FROM organization_dff_step1
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
  work_rel.PeriodOfServiceId AS id_period_of_service,
  work_rel.AssignmentId AS id_assignment,
  work_rel.DepartmentId AS id_department,
  work_rel.JobId AS id_job,
  salaries.id_salary,
  managers_data.id_person_manager,
  ew.EmailAddressId AS id_work_email,
  eh.EmailAddressId AS id_personal_email,
  phones.PhoneId AS id_phone,
  addresses.AddressId AS id_address,
  work_rel.ManagerAssignmentId AS id_assignment_manager,
  ethnicities.EthnicityId AS id_ethnicity,
  work_rel.id_person_hrbp,
  workers.person_number,
  work_rel.AssignmentNumber AS assignment_number,
  -- -- non metric
  -- -- name information,
  names.FirstName AS first_name,
  names.LastName AS last_name,
  names.FullName AS full_name,
  names.NameInformation15 AS first_social_name,
  names.NameInformation16 AS last_social_name,
  -- -- assignment info,
  CASE
    WHEN work_rel.ActionCode = 'RESIGNATION'
      THEN 'Desligamento Voluntário'
    WHEN work_rel.ActionCode = 'TERMINATION'
      THEN 'Desligamento Involuntário'
    WHEN work_rel.ActionCode = 'DEATH'
      THEN 'Falecimento'
  END AS dismissal_type,
  work_rel.AssignmentName AS assignment_name,
  work_rel.WorkerType AS worker_type,
  work_rel.LegalEmployerName AS legal_employer_name,
  work_rel.BusinessUnitName AS business_unit_name,
  work_rel.marcaProduto AS brand,
  NVL(work_rel.AssignmentStatusType, 'PENDING') AS assignment_status_type,
  work_rel.DepartmentName AS department_name,
  work_rel.JobCode AS job_code,
  work_rel.AssignmentCategory AS assignment_category,
  work_rel.ActionCode AS action_code,
  work_rel.ReasonCode AS reason_code,
  arl.action_reason AS reason_code_description,
  work_rel.GradeCode AS band,
  work_rel.GradeLadderName AS band_ladder_name,
  work_rel.trilha AS track,
  odff.subDiretoria AS sub_board,
  odff.diretoria AS board,
  odff.vicePresidencia AS vice_presidency,
  odff.vertical,
  odff.business,
  odff.product,
  salaries.currency_code,
  work_rel.LegislationCode AS legislation_code,
  work_rel.assignment_number_hrbp,
  work_rel.responsibility_name_hrbp,
  -- -- -- Managers,
  work_rel.ManagerAssignmentNumber AS manager_assignment_number,
  managers_data.person_number_manager AS manager_person_number,
  managers_data.FullNameManager AS manager_full_name,
  managers_data.EmailManager AS email_manager,
  -- -- birth info,
  workers.birth_town,
  workers.birth_region,
  workers.birth_country,
  -- -- docs info,
  ni2_cpf.NationalIdentifierNumber AS cpf,
  ni2_rg.NationalIdentifierNumber AS rg,
  ni2_pis.NationalIdentifierNumber AS pis,
  nidff.ufDeEmissao AS issuing_state_rg,
  nidff.orgaoDeEmissao AS issuing_authority_rg,
  li.ctpsNumber AS ctps_number,
  li.ctpsSeries AS ctps_series,
  li.issuingState AS issuing_state_ctps,
  li.numeroDoTituloDeEleitor AS vote_registration_number,
  li.zonaEleitoralDoTitulo AS electoral_zone,
  li.secaoEleitoralDoTitulo AS polling_station,
  -- -- personal info,
  wdff.nomeDaMae AS mother_name,
  wdff.nomeDoPai AS father_name,
  ethnicities.Ethnicity AS ethnicity,
  CASE 
    WHEN ethnicities.Ethnicity = '1' THEN 'Indígena'
    WHEN ethnicities.Ethnicity = '2' THEN 'Branca'
    WHEN ethnicities.Ethnicity = '4' THEN 'Preta'
    WHEN ethnicities.Ethnicity = '6' THEN 'Amarela'
    WHEN ethnicities.Ethnicity = '8' THEN 'Parda'
    WHEN ethnicities.Ethnicity = '9' THEN 'Não informado'
    WHEN ethnicities.Ethnicity = '15' THEN 'Negro'
    WHEN ethnicities.Ethnicity = 'ORA_HRX_MIXED' THEN 'Misto'
    WHEN ethnicities.Ethnicity = '60' THEN 'Nativo'
    WHEN ethnicities.Ethnicity = 'ORA_HRX_BRIN' THEN 'Índio Brasileiro'
    WHEN ethnicities.Ethnicity = '20' THEN 'Moreno'
    ELSE NULL
  END  AS ethnicity_description,
  li.MaritalStatus AS marital_status,
  CASE 
    WHEN MaritalStatus = 'C' THEN 'Casado(a)'
    WHEN MaritalStatus = 'D' THEN 'Divorciado(a)'
    WHEN MaritalStatus = 'M' THEN 'União Estável'
    WHEN MaritalStatus = 'O' THEN 'Outros'
    WHEN MaritalStatus = 'Q' THEN 'Desquitado(a) / Separado(a)'
    WHEN MaritalStatus = 'S' THEN 'Solteiro'
    WHEN MaritalStatus = 'V' THEN 'Viúvo(a)'
    WHEN MaritalStatus = 'N' THEN 'Não informado'
    WHEN MaritalStatus = 'ORA_HRX_SEP' THEN 'Separado(a)'
    ELSE 'Unknown Marital Status'
  END AS marital_status_description,
  li.Gender AS gender,
  li.orientacaoSexual AS sexual_orientation,
  li.genero AS gender_identity,
  li.neurodiversidade AS neurodiversity,
  religions.Religion AS religion,
  CASE
    WHEN religions.Religion='Agnosticismo' THEN 'Agnosticismo'
    WHEN religions.Religion='Ateísmo' THEN 'Ateísmo'
    WHEN religions.Religion='Candomblé' THEN 'Candomblé'
    WHEN religions.Religion='Mórmon' THEN 'Mórmon'
    WHEN religions.Religion='ORA_HRX_CATHOLICISM' THEN 'Catolicismo'
    WHEN religions.Religion='OTHER' THEN 'Outra'
    WHEN religions.Religion='Umbanda' THEN 'Umbanda'
    WHEN religions.Religion='CHRISTIAN' THEN LOWER(religions.Religion)
    WHEN religions.Religion='NONE' THEN NULL
    ELSE religions.Religion
  END AS religion_name,
  li.HighestEducationLevel AS highest_education_level_code,
  CASE  
    WHEN li.HighestEducationLevel = 10 THEN 'Analfabeto, inclusive o que, embora tenha recebido instrução, não se alfabetizou'
    WHEN li.HighestEducationLevel = 20 THEN 'Até o 5º ano incompleto do Ensino Fundamental (antiga 4ª série) ou que se tenha alfabetizado sem ter   frequentado escola regular'
    WHEN li.HighestEducationLevel = 25 THEN '5º ano completo do Ensino Fundamental'
    WHEN li.HighestEducationLevel = 30 THEN 'Do 6º ao 9º ano do Ensino Fundamental incompleto (antiga 5ª à 8ª série)'
    WHEN li.HighestEducationLevel = 35 THEN 'Ensino Fundamental completo'
    WHEN li.HighestEducationLevel = 40 THEN 'Ensino Médio incompleto'
    WHEN li.HighestEducationLevel = 45 THEN 'Ensino Médio completo'
    WHEN li.HighestEducationLevel = 807 THEN 'Técnico incompleto'
    WHEN li.HighestEducationLevel = 803 THEN 'Tecnólogo incompleto'
    WHEN li.HighestEducationLevel = 809 THEN 'Técnico completo'
    WHEN li.HighestEducationLevel = 805 THEN 'Tecnólogo completo'
    WHEN li.HighestEducationLevel = 50 THEN 'Educação Superior incompleta'
    WHEN li.HighestEducationLevel = 55 THEN 'Educação Superior completa'
    WHEN li.HighestEducationLevel = 801 THEN 'Pós-graduação incompleta'
    WHEN li.HighestEducationLevel = 85 THEN 'Pós-graduação completa'
    WHEN li.HighestEducationLevel = 800 THEN 'Mestrado incompleto'
    WHEN li.HighestEducationLevel = 65 THEN 'Mestrado completo'
    WHEN li.HighestEducationLevel = 13 THEN 'Doutorado incompleto'
    WHEN li.HighestEducationLevel = 75 THEN 'Doutorado completo'
    ELSE NULL
  END as highest_education_level_name,
  -- -- -- contacts,
  ew.EmailAddress as work_email,
  eh.EmailAddress AS personal_email,
  phones.CountryCodeNumber AS country_code_number,
  phones.AreaCode AS area_code,
  phones.PhoneNumber AS phone_number,
  -- -- address,
  CONCAT(addresses.AddlAddressAttribute3, ' ', addresses.AddressLine1) AS address,
  addresses.AddressLine2 AS address_number,
  addresses.AddressLine3 AS address_complement,
  addresses.AddressLine4 AS address_district,
  addresses.PostalCode AS address_zip_code,
  addresses.TownOrCity AS address_city,
  addresses.Region2 AS address_state,
  addresses.Country AS address_country,
  -- -- -- metrics,,
  boolean(work_rel.ManagerFlag) AS is_manager,
  CASE 
    WHEN work_rel.funcionarioMarcaPonto = 1
      THEN TRUE
    WHEN work_rel.funcionarioMarcaPonto = 0
      THEN FALSE
    ELSE NULL
  END AS has_clock_in,
  CASE 
    WHEN li.possuiAlgumaDeficiencia = 'Sim'
      THEN TRUE
    WHEN li.possuiAlgumaDeficiencia = 'Não'
      THEN FALSE
    ELSE NULL 
  END AS has_disability,
  CASE 
    WHEN desejaReceberAdiantamentoSalar = 'S'
      THEN TRUE
    WHEN desejaReceberAdiantamentoSalar = 'N'
      THEN FALSE
    ELSE NULL
  END AS has_salary_advance,
  salaries.salary_amount,
  FLOAT(work_rel.targetPlr) AS target_plr,
  -- -- dates
  DATE(workers.dt_birth) AS dt_birth,
  DATE(work_rel.TerminationDate) AS dt_termination_work_relationship,
  DATE(work_rel.StartDate) AS dt_start_work_relationship,
  DATE(work_rel.NotificationDate) AS dt_notification,
  DATE(work_rel.EffectiveStartDate) AS dt_assignment_effective_start,
  DATE(work_rel.dataFinalDaExperiencia1) AS dt_experience_period_1,
  DATE(work_rel.dataFinalDaExperiencia2) AS dt_experience_period_2,
  NOW() AS ts_load
FROM hr_system_workers as workers
JOIN 
  work_relationship_data as work_rel
    ON workers.id_person = work_rel.id_person
LEFT JOIN 
  salaries
    ON work_rel.AssignmentId = salaries.id_assignment
LEFT JOIN 
  ethnicities
    ON workers.id_person = ethnicities.id_person
    AND work_rel.LegislationCode = ethnicities.LegislationCode
LEFT JOIN 
  legislative_info_data AS li
    ON workers.id_person = li.id_person
    AND work_rel.LegislationCode = li.LegislationCode
LEFT JOIN 
  emails as ew
    ON workers.id_person = ew.id_person
    AND ew.EmailType = 'W1'
LEFT JOIN 
  emails as eh
    ON workers.id_person = eh.id_person
    AND eh.EmailType = 'H1'
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
    AND work_rel.PeriodOfServiceId = managers_data.PeriodOfServiceId
    AND work_rel.AssignmentId = managers_data.AssignmentId
LEFT JOIN 
  religions 
    ON workers.id_person = religions.id_person
    AND work_rel.LegislationCode = religions.LegislationCode
LEFT JOIN 
  organization_dff odff
    ON work_rel.DepartmentId = odff.id_organization
LEFT JOIN 
  datalake_hr_system_clean.action_reasons_lov arl
    ON work_rel.ReasonCode = arl.action_reason_code
LEFT JOIN 
  external_identifiers ei 
    ON workers.id_person = ei.id_person
LEFT JOIN 
  national_identifiers_step2  ni2_cpf
    ON workers.id_person = ni2_cpf.id_person
    AND ni2_cpf.NationalIdentifierType = 'CPF'
LEFT JOIN 
  national_identifiers_step2  ni2_rg
    ON workers.id_person = ni2_rg.id_person
    AND ni2_rg.NationalIdentifierType = 'RG'
LEFT JOIN 
  national_identifiers_step2 ni2_pis
    ON workers.id_person = ni2_pis.id_person
    AND ni2_pis.NationalIdentifierType = 'PIS'
LEFT JOIN 
  nationalIdentifiersDFF nidff
    ON workers.id_person = nidff.id_person 
    AND ni2_rg.NationalIdentifierId = nidff.NationalIdentifierId
WHERE ei.id_person is null
