SELECT
    id,
    negotiation_id AS id_negotiation,
    business_entity_id AS id_business_entity,
    finance_entity_id AS id_finance_entity,
    domain,
    write_off_at AS dt_write_off,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_negotiation_raw.negotiation_item
