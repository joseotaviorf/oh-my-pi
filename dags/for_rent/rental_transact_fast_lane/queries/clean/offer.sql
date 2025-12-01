SELECT
    id,
    firestore_offer_id AS id_firestore_offer,
    house_external_id AS id_house_external,
    tenant_external_id AS id_tenant_external,
    owner_external_id AS id_owner_external,
    resident_info_id AS id_resident_info,
    offer_uuid AS uuid_offer,
    status,
    type,
    iteration,
    turn,
    rejection_reason,
    original_rent_value,
    payment_flow_type,
    original_iptu_value,
    original_condominium_value,
    original_home_insurance_value,
    original_tenant_service_fee_value,
    created_at AS ts_created,
    updated_at AS ts_updated,
    expires_at AS ts_expiration
FROM
    datalake_rental_transact_raw.offer