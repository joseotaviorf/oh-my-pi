SELECT
    id                          AS id_operation,
    feature_id                  AS id_feature,
    business_partner_id         AS id_business_partner,
    sync_sap_job_id             AS id_sync_sap_job,
    `description`,
    feature_op_ident,
    TIMESTAMP(reference_date)   AS ts_reference,
    TIMESTAMP(due_date)         AS ts_due,
    created_at                  AS ts_created,
    updated_at                  AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sap_gateway_homolog_raw.operation
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
