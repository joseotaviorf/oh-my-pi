SELECT
    id,
    coordinateId AS id_coordinate,
    salesForceId AS id_salesforce,
    cidade_id AS id_city,
    workContract_id AS id_work_contract,
    preferredRegion_id AS id_preferred_region,
    companyUuid AS uuid_company,
    code,
    perfil AS profile,
    tipoAgente AS agent_type,
    cargoImobiliaria AS position_in_real_estate_agency,
    identificacaoImobiliaria AS real_estate_agency,
    numeroCRECI AS creci_number,
    ativo AS is_active,
    edicaoAgendaBloqueada AS is_blocked_schedule_edition,
    passiveLeadReceiver AS is_passive_lead_receiver,
    serviceLinkActive AS is_service_link_active,
    opted_for_online_support AS has_opted_for_online_support,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.dadosagente