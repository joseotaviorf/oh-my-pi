SELECT
    entity_id AS id_entity,
    prediction_id AS id_prediction,
    model_name,
    p10,
    p20,
    p30,
    p40,
    p50,
    p60,
    p70,
    p80,
    p90,
    prediction_certainty,
    house_dejavuid,
    condo_dejavuid,
    prediction_metadata,
    business_context,
    house_id AS id_house,
    model_version,
    created_at AS ts_created,
    inbox_message_id AS id_inbox_message
FROM
    datalake_pricing_raw.price_prediction

