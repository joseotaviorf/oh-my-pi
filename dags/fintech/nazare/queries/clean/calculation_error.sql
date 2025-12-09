SELECT
    id AS id_calculation_error,
    offer_agent_id AS id_offer_agent,
    offer_partner_id AS id_offer_partner,
    offer_id AS id_offer,
    type,
    message,
    metadata,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(solved_at) AS ts_solved
FROM
    datalake_nazare_raw.calculation_error
