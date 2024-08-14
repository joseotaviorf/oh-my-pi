SELECT 
    id,
    tenant_external_id AS id_tenant_external,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    introduction,
    number_of_cohabitants,
    tenant_external_id_mod AS mod_id_tenant_external
    introduction_mod AS mod_introduction,
    number_of_cohabitants_mod AS mod_number_of_cohabitants,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_transact_raw.resident_info_aud