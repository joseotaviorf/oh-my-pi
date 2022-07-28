SELECT
    id,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated,
    codigo AS code,
    dia AS dt_visit,
    slot,
    numeroSlots AS slot_count,
    tipo AS type,
    agenteFixo AS is_fixed_agent,
    realEstateAgentRating_id AS id_real_estate_agent_rating,
    status,
    bookingType AS booking_type,
    visitante_id AS id_visitor,
    agente_id AS id_agent,
    origemCriacao_id AS id_creation_origin,
    origemUltimaAtualizacao_id AS id_last_update_origin,
    houseRating_id AS id_house_rating
FROM
    datalake_ebdb_raw.Visita
