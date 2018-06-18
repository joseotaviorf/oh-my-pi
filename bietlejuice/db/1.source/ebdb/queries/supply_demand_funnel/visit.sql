 select
    id,
    criadoEm,
    atualizadoEm,
    codigo,
    dia,
    slot,
    numeroSlots,
    tipo,
    agenteFixo,
    realEstateAgentRating_id,
    status,
    bookingType
  from
    Visita v
where coalesce(v.criadoEm, '1900-01-01 00:00:00') < '{}'