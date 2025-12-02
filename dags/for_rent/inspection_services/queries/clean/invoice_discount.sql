SELECT
    discount_uuid AS uuid_discount,
    contract_id AS id_contract,
    inspection_uuid AS uuid_inspection,
    checkpoint_id AS id_checkpoint,
    user_id AS id_user,
    person_uuid AS uuid_person,
    discount_type,
    inspection_cost,
    disputed_inspection_cost,
    discount_value,
    discount_hash,
    discount_value_type,
    tenant_approval AS has_tenant_approval,
    landlord_approval AS has_landlord_approval,
    landlord_repair_request AS has_landlord_repair_request,
    is_eviction,
    is_spoc,
    person_blocked,
    person_blocked_reason,
    discount_accepted AS is_discount_accepted,
    discount_reviewed_value,
    discount_accepted_at AS dt_discount_accepted,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_inspection_services_raw.invoice_discount

