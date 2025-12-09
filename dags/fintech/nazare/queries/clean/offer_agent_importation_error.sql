SELECT
    id AS id_offer_agent_importation_error,
    offer_id AS id_offer,
    error_messages,
    original_value,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.offer_agent_importation_error
