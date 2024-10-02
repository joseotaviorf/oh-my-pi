SELECT
    id AS id_visit,
    REV AS rev,
    rEVTYPE AS rev_type,
    agente_id AS id_agent,
    origemUltimaAtualizacao_id AS id_last_update_origin,
    agenteFixo AS is_fixed_agent,
    realEstateAgentRating_id AS id_real_estate_agent_rating,
    status,
    structured,
    computed_status,
    structured_MOD AS mod_structured,
    status_MOD AS mod_status,
    bookingType AS booking_type,
    houseRating_id AS id_house_rating,
    origemCriacao_id AS id_creation_origin
FROM
    datalake_ebdb_test_raw.Visita_AUD
