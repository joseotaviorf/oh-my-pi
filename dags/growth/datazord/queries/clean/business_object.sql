SELECT
    surrogate_key AS sk_business_object,
    id_user,
    uuid_person,
    id_house,
    id_contract,
    id_object,
    business_type,
    persona,
    is_active,
    house_address,
    properties,
    business_context,
    journey_step,
    inactive_at AS ts_inactive,
    ts_created,
    ts_updated
FROM
    datalake_datazord_raw.business_object
