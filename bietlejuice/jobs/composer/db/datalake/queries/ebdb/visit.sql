SELECT
    id AS id_visit,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated,
    codigo AS cd_visit,
    dia AS dt_visit,
    slot,
    numeroSlots AS slot_count,
    tipo AS type,
    agenteFixo AS fixed_agent,
    realEstateAgentRating_id AS id_real_state_agent_rating,
    status,
    bookingType AS booking_type
FROM
    datalake_ebdb_raw.visita
