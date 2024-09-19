SELECT
    id,
    workContract_id AS id_work_contract,
    preferredRegion_id AS id_preferred_region,
    perfil AS profile,
    tipoAgente AS agent_type,
    cargoImobiliaria AS position_in_real_estate_agency,
    identificacaoImobiliaria AS real_estate_agency,
    numeroCRECI AS creci_number,
    rev,
    revtype AS rev_type,
    ativo AS is_active,
    edicaoAgendaBloqueada AS is_schedule_blocked,
    opted_for_online_support AS has_opted_for_online_support,
    tipoAgente_MOD AS mod_agent_type,
    cargoImobiliaria_MOD AS mod_position_in_real_estate_agency,
    identificacaoImobiliaria_MOD AS mod_real_estate_agency,
    numeroCRECI_MOD AS mod_creci_number,
    opted_for_online_support_MOD AS has_opted_for_online_support_MOD
FROM
    datalake_ebdb_raw.dadosagente_aud 