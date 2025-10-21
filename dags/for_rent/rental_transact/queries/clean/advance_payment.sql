SELECT
    id,
    advance_payment_uuid as uuid_advance_payment,
    house_external_id as id_house_external,
    tenant_external_id as id_tenant_external,
    owner_external_id as id_owner_external,
    rent_flow_uuid as uuid_offer,
    status,
    rejection_reason,
    payment_percentage,
    payment_amount,
    created_at as ts_created,
    updated_at as ts_updated,
    expires_at as ts_expires,
    cancelled_at as ts_cancelled
FROM
    datalake_rental_transact_raw.advance_payment
