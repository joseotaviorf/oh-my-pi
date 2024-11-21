SELECT
    id                          AS id_business_partner,
    person_id                   AS id_person,
    address_id                  AS id_address,
    sync_sap_job_id             AS id_sync_sap_job,
    `type`,
    synced_at                   AS ts_synced,
    created_at                  AS ts_created,
    updated_at                  AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.business_partner
