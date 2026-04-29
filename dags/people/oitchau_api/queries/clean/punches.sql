SELECT
    id AS id_punch,
    uuid AS id_punch_key,
    CAST(createdBy.id AS BIGINT) AS id_created_by,
    createdBy.uuid AS id_created_by_profile,
    createdBy.externalId AS id_created_by_external,
    CAST(employee.id AS BIGINT) AS id_employee,
    employee.uuid AS id_employee_profile,
    employee.externalId AS id_employee_external,
    locationId AS id_location,
    `key` AS punch_key,
    timezone AS timezone_name,
    `type` AS punch_type,
    status AS punch_status,
    reason AS punch_reason,
    source AS punch_source,
    validation AS validation_status,
    lateReason AS late_reason,
    comment AS punch_comment,
    minutes AS duration_minutes,
    createdBy.cpf AS created_by_national_tax_number,
    createdBy.fullName AS created_by_full_name,
    createdBy.matricula AS created_by_registration_code,
    createdBy.pis AS created_by_pis_number,
    employee.cpf AS employee_national_tax_number,
    employee.fullName AS employee_full_name,
    employee.matricula AS employee_registration_code,
    employee.pis AS employee_pis_number,
    manual AS is_manual_adjustment,
    customLocation AS is_custom_location,
    forceValidated AS is_force_validated,
    CAST(`date` AS DATE) AS dt_punched,
    `time` AS punch_time_local,
    ts_load,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.punches
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
        AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY id
        ORDER BY
            ts_load DESC NULLS LAST,
            year DESC,
            month DESC,
            day DESC
    ) = 1
