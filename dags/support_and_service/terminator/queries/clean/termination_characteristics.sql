SELECT 
    id,
    termination_id AS id_termination,
    job_transfer AS is_job_transfer,
    before_rental AS is_before_rental,
    internal_administration AS is_internal_administration,
    tenant_condominium_payer AS is_tenant_condominium_payer,
    pro_owner AS is_pro_owner,
    termination_in_first_year AS is_termination_in_first_year,
    notice_due AS is_notice_due,
    eviction AS is_eviction,
    landlord_selling AS is_landlord_selling,
    inspection_opted_out AS is_inspection_opted_out,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_terminator_raw.termination_characteristics
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}