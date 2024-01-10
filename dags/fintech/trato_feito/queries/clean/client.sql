SELECT
    id,
    external_id AS id_external,
    contract_id AS id_contract,
    status_syncs,
    creditor,
    document,
    document_type,
    marital_status,
    name,
    birth_date,
    phones,
    emails,
    client_type,
    debtor_origin,
    will_live_in_place,
    created_at AS dt_created,
    updated_at AS dt_updated
FROM datalake_trato_feito_raw.client
