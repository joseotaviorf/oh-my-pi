SELECT
    id,
    rev,
    revtype as rev_type,
    ativo as is_active,
    edicaoAgendaBloqueada as is_schedule_blocked,
    perfil as profile,
    workContract_id as id_work_contract,
    preferredRegion_id as id_preferred_region,
    numeroCRECI as creci_number,
    numeroCRECI_MOD as mod_creci_number
FROM datalake_ebdb_raw.dadosagente_aud 