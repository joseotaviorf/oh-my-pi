SELECT
    id,
    cart_uuid AS uuid_cart,
    third_party_bills_id AS id_third_party_bills,
    contractual_penalty,
    amount,
    currency,
    status,
    cart_idempotency_key,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.billback
