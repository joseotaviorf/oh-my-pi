-- Widened to the full AGREEMENT payload so RAW acordos in the extraction spreadsheet maps
-- one to one onto this projection.
-- The spreadsheet column id_recebimento_recb is the vendor key id_parcela_acp: all 78 values
-- in production resolve to a CHARGE natural key. id_recebimento_recb1 is the duplicate the
-- vendor portal returns, same value, kept so the shapes line up.
-- PK is id_acordo_aco | id_parcela_acp; id_acordo_aco groups the instalments.
WITH agreement_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key,
        CAST(lake_mirror.payload AS STRING) AS payload_json,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_parcela_acp') AS id_parcela_acp,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_sacado_sac') AS id_sacado_sac,
        lake_mirror.synced_at
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'AGREEMENT'
),
tenant_by_sacado AS (
    SELECT
        locatario.id_pessoa_pes,
        locatario.id_sacado_sac,
        ROW_NUMBER() OVER (
            PARTITION BY locatario.id_sacado_sac
            ORDER BY locatario.id
        ) AS rn
    FROM
        datalake_benvi_manager_clean.benvi_superlogica_locatario AS locatario
    WHERE
        locatario.id_sacado_sac IS NOT NULL
)
SELECT
    agreement_row.id,
    agreement_row.vendor_natural_key,
    get_json_object(agreement_row.payload_json, '$.id_acordo_aco') AS id_acordo_aco,
    agreement_row.id_parcela_acp,
    agreement_row.id_parcela_acp AS id_recebimento_recb,
    agreement_row.id_parcela_acp AS id_recebimento_recb1,
    agreement_row.id_sacado_sac,
    tenant_by_sacado.id_pessoa_pes,
    cobranca.id_contrato_con,
    get_json_object(agreement_row.payload_json, '$.nm_nfse_not') AS nm_nfse_not,
    get_json_object(agreement_row.payload_json, '$.nm_nfe_not') AS nm_nfe_not,
    get_json_object(agreement_row.payload_json, '$.id_nota_not') AS id_nota_not,
    get_json_object(agreement_row.payload_json, '$.st_sincro_sac') AS st_sincro_sac,
    CAST(get_json_object(agreement_row.payload_json, '$.fl_tipo_acoi') AS INT) AS fl_tipo_acoi,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_competencia_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_competencia_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_competencia_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_vencimento_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_vencimento_recb,
    CAST(get_json_object(agreement_row.payload_json, '$.vl_total_recb') AS DOUBLE) AS vl_total_recb,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_liquidacao_recb'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_liquidacao_recb,
    CAST(get_json_object(agreement_row.payload_json, '$.fl_status_recb') AS INT) AS fl_status_recb,
    get_json_object(agreement_row.payload_json, '$.st_label_recb') AS st_label_recb,
    get_json_object(agreement_row.payload_json, '$.id_acordo_aco1') AS id_acordo_aco1,
    get_json_object(agreement_row.payload_json, '$.st_descricao_aco') AS st_descricao_aco,
    get_json_object(agreement_row.payload_json, '$.id_empresa_emp') AS id_empresa_emp,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_acordo_aco'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_acordo_aco'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_acordo_aco,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_desfeito_aco'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(agreement_row.payload_json, '$.dt_desfeito_aco'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_desfeito_aco,
    get_json_object(agreement_row.payload_json, '$.nm_parcela_aco') AS nm_parcela_aco,
    get_json_object(agreement_row.payload_json, '$.tx_itens_aco') AS tx_itens_aco,
    get_json_object(agreement_row.payload_json, '$.tx_juros_aco') AS tx_juros_aco,
    get_json_object(agreement_row.payload_json, '$.id_transacao_ctr') AS id_transacao_ctr,
    get_json_object(agreement_row.payload_json, '$.nome_formatado') AS nome_formatado,
    get_json_object(agreement_row.payload_json, '$.st_cgc_sac') AS st_cgc_sac,
    get_json_object(agreement_row.payload_json, '$.st_nome_sac') AS st_nome_sac,
    get_json_object(agreement_row.payload_json, '$.st_nomeref_sac') AS st_nomeref_sac,
    get_json_object(agreement_row.payload_json, '$.st_observacaoexterna_recb') AS st_observacaoexterna_recb,
    get_json_object(agreement_row.payload_json, '$.st_observacaointerna_recb') AS st_observacaointerna_recb,
    agreement_row.synced_at AS ts_synced
FROM
    agreement_row AS agreement_row
LEFT JOIN
    tenant_by_sacado AS tenant_by_sacado
        ON agreement_row.id_sacado_sac = tenant_by_sacado.id_sacado_sac
        AND tenant_by_sacado.rn = 1
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_cobranca AS cobranca
        ON agreement_row.id_parcela_acp = cobranca.id_recebimento_recb
