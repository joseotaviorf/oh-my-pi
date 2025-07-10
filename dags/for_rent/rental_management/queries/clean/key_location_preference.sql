SELECT
    id,
    key_location_preference_uuid AS uuid_key_location_preference,
    contract_id AS id_contract,
    termination_id AS id_termination,
    key_holder_preference_id AS id_key_holder_preference,
    key_location_return_address_id AS id_key_location_return_address,
    access_key,
    observation,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.key_location_preference
