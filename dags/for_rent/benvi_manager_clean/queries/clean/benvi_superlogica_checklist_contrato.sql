-- Widened to the full CONTRACT_CHECKLIST_ITEM payload so RAW checklist_itens in the
-- extraction spreadsheet maps one to one onto this projection.
-- Grain is contract by checklist by item; join id_contrato_con to benvi_superlogica_contrato.
WITH checklist_row AS (
    SELECT
        id,
        vendor_natural_key,
        CAST(payload AS STRING) AS payload_json,
        synced_at
    FROM
        datalake_benvi_manager_raw.lake_mirror
    WHERE
        resource_code = 'CONTRACT_CHECKLIST_ITEM'
)
SELECT
    id,
    vendor_natural_key,
    get_json_object(payload_json, '$.id_contrato_con') AS id_contrato_con,
    get_json_object(payload_json, '$.id_checklist_chk') AS id_checklist_chk,
    get_json_object(payload_json, '$.id_checklistitem_chi') AS id_checklistitem_chi,
    get_json_object(payload_json, '$.st_nome_chk') AS st_nome_chk,
    CAST(get_json_object(payload_json, '$.fl_notificar_chk') AS INT) AS fl_notificar_chk,
    get_json_object(payload_json, '$.id_imovel_imo') AS id_imovel_imo,
    CAST(get_json_object(payload_json, '$.fl_principal_prb') AS INT) AS fl_principal_prb,
    CAST(get_json_object(payload_json, '$.fl_proprietario_prb') AS INT) AS fl_proprietario_prb,
    get_json_object(payload_json, '$.st_nome_proprietario_imo') AS st_nome_proprietario_imo,
    get_json_object(payload_json, '$.id_proprietario_imo') AS id_proprietario_imo,
    get_json_object(payload_json, '$.st_email_proprietario_imo') AS st_email_proprietario_imo,
    get_json_object(payload_json, '$.id_sacado_proprietario') AS id_sacado_proprietario,
    get_json_object(payload_json, '$.st_nome_cch') AS st_nome_cch,
    CAST(get_json_object(payload_json, '$.fl_status_cch') AS INT) AS fl_status_cch,
    CAST(get_json_object(payload_json, '$.fl_responsavel_cch') AS INT) AS fl_responsavel_cch,
    get_json_object(payload_json, '$.nm_periodonotificacao_cch') AS nm_periodonotificacao_cch,
    CAST(get_json_object(payload_json, '$.fl_tiponotificacao_cch') AS INT) AS fl_tiponotificacao_cch,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_ultimanotificacao_cch'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_ultimanotificacao_cch'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_ultimanotificacao_cch,
    get_json_object(payload_json, '$.st_observacao_cch') AS st_observacao_cch,
    CAST(get_json_object(payload_json, '$.fl_comprovanteobrigatorio_cch') AS INT) AS fl_comprovanteobrigatorio_cch,
    CAST(get_json_object(payload_json, '$.fl_exibirnoapp_cch') AS INT) AS fl_exibirnoapp_cch,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_entregalimite_cch'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_entregalimite_cch'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_entregalimite_cch,
    get_json_object(payload_json, '$.st_motivoreprovacao_cch') AS st_motivoreprovacao_cch,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_envioapp_cch'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_envioapp_cch'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_envioapp_cch,
    synced_at AS ts_synced
FROM
    checklist_row
