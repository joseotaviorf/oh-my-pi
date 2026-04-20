SELECT
    uuid AS id_employee_profile,
    id AS id_employee,
    externalId AS id_external,
    companyUuid AS id_company,
    CAST(department.id AS BIGINT) AS id_department,
    department.uuid AS id_department_key,
    ownTeamUuid AS id_own_team,
    teamUuid AS id_team,
    CAST(position.id AS BIGINT) AS id_position,
    position.uuid AS id_position_key,
    position.externalId AS id_position_external,
    CAST(subsidiary.id AS BIGINT) AS id_subsidiary,
    subsidiary.uuid AS id_subsidiary_key,
    subsidiary.taxPayerId AS id_subsidiary_taxpayer,
    CAST(supervisor.id AS BIGINT) AS id_supervisor,
    supervisor.uuid AS id_supervisor_key,
    supervisor.externalId AS id_supervisor_external,
    avatarId AS id_avatar_cloudinary,
    matricula AS registration_code,
    department.code AS department_code,
    department.name AS department_name,
    subsidiary.code AS subsidiary_code,
    subsidiary.name AS subsidiary_name,
    position.title AS position_title,
    supervisor.fullName AS supervisor_full_name,
    supervisor.matricula AS supervisor_registration_code,
    supervisor.pis AS supervisor_pis_number,
    cpf AS employee_national_tax_number,
    pis AS pis_number,
    fullName AS full_name,
    jobTitle AS job_title,
    role AS role_name,
    contractedHoursPerWeek AS contracted_hours_per_week,
    defaultTimeZone AS timezone_default,
    avatarVersion AS avatar_version,
    projectEmployeeCost AS project_employee_cost,
    active AS is_active,
    birthDate AS dt_birth,
    startDate AS dt_hired,
    deactivateDate AS dt_deactivated,
    lastLockDate AS dt_last_timesheet_locked,
    updatedAt AS ts_updated,
    associateProducts AS associate_products,
    roleUuids AS role_ids,
    locations,
    ts_load,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.employees
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
        AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY uuid
        ORDER BY
            ts_load DESC
    ) = 1
