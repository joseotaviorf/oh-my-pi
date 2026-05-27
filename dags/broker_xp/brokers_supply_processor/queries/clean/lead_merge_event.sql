SELECT
    id AS id_lead_merge_event,
    existing_lead_uuid AS uuid_existing_lead,
    cnpj,
    existing_id_by_real_estate AS id_by_real_estate_existing,
    payload_id_by_real_estate AS id_by_real_estate_payload,
    existing_lead_hash AS lead_hash_existing,
    payload_lead_hash AS lead_hash_payload,
    match_criterion,
    source,
    created_at AS ts_created,
    existing_contexts,
    incoming_contexts,
    new_contexts,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.lead_merge_event
