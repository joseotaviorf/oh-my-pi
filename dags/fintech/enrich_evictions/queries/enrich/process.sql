SELECT
    id_anonymized AS id_anonymized,
    NULL AS id_case,
    contract AS id_contract,
    action_type AS process_type,
    office AS law_firm,
    "Cyber Legal" AS source,
    CASE
        WHEN action_type = "Despejo" AND last_process_stage IS NOT NULL THEN CONCAT(action_type, " ", last_process_stage)
        ELSE  "INITIATED"
    END AS status,
    CASE WHEN elaw_status = 'Ativo' THEN TRUE ELSE FALSE END AS is_active,
    NULL AS status_order,
    last_process_stage,
    NULL AS ts_created,
    GREATEST(stage_distribuicao_arbitral_dt_start, stage_distribuicao_arbitral_dt_end, stage_citacao_arbitral_dt_start, stage_citacao_arbitral_dt_end, stage_sentenca_arbitral_dt_start, stage_sentenca_arbitral_dt_end, stage_distribuicao_judicial_dt_start, stage_distribuicao_judicial_dt_end, stage_decisao_citacao_judicial_dt_start, stage_decisao_citacao_judicial_dt_end, stage_citacao_judicial_dt_start, stage_citacao_judicial_dt_end, stage_decisao_coercitivo_dt_start, stage_decisao_coercitivo_dt_end, stage_emissao_coercitivo_dt_start, stage_emissao_coercitivo_dt_end) AS ts_last_update_event,
    ts_updated
FROM datalake_cyber_legal_homolog.evictions_base

UNION ALL

SELECT
    id_anonymized AS id_anonymized,
    id_process AS id_case,
    contract AS id_contract,
    process AS process_type,
    office AS law_firm,
    "E-law" AS source,
    last_stage AS status,
    CASE WHEN elaw_status = 'Ativo' THEN TRUE ELSE FALSE END AS is_active,
    NULL AS status_order,
    last_stage AS last_process_stage,
    TIMESTAMP(dt_registered) AS ts_created,
    GREATEST(dt_arbitral_distribution, dt_arbitral_citation, dt_arbitral_contestation, dt_arbitral_sentence, dt_judiciary_pre_registration, dt_judiciary_distribution, dt_judicial_summons_decision, dt_judicial_summons, dt_judicial_defense, dt_coercive_decision, dt_coercive_issuance) AS ts_last_update_event,
    GREATEST(dt_arbitral_distribution, dt_arbitral_citation, dt_arbitral_contestation, dt_arbitral_sentence, dt_judiciary_pre_registration, dt_judiciary_distribution, dt_judicial_summons_decision, dt_judicial_summons, dt_judicial_defense, dt_coercive_decision, dt_coercive_issuance, dt_finalizing, dt_finalized_erc, dt_elaw_closure) AS ts_updated
FROM datalake_gsheets_clean.evictions_base

UNION ALL

SELECT
    NULL AS id_anonymized,
    id_external AS id_case,
    CASE WHEN entity_type = 'CONTRACT' THEN id_entity END AS id_contract,
    process_type,
    law_firm,
    "Chargehub" AS source,
    status,
    CASE WHEN is_active = 'TRUE' THEN TRUE ELSE FALSE END AS is_active,
    status_order,
    NULL AS last_process_stage,
    ts_created,
    ts_last_update_event,
    ts_updated
FROM datalake_gsheets_clean.legal_process
