SELECT
    id,
    idempresa AS id_company,
    iddevedor AS id_debtor,
    processo AS process,
    status_cod,
    reaberto_codimp AS cod_imp_reopen,
    status_desc,
    obs,
    agenda_data AS dt_schedule,
    agenda_hora AS hr_schedule,
    agenda_obs AS obs_schedule,
    ocorrencia_ultima AS last_occurrence,
    status_negociador AS status_negociator,
    status_cod_bkp,
    status_desc_bkp,
    agenda_negociador AS negociator_schedule,
    ocorrencia_ultimo_status AS occurrence_last_status,
    fase AS phase,
    reaberto_data AS dt_reopened,
    last_update AS ts_updated
FROM
    datalake_iaf_raw.vi_319_tb_processo
