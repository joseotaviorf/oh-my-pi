-- Join PAYOUT.id_contrato_con to contrato, id_recebimento_recb to cobranca,
-- id_locatario_pes to locatario.vendor_natural_key (id_pessoa_pes).
WITH payout_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_repasse_rep,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recebimento_recb') AS id_recebimento_recb,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_locatario_pes') AS id_locatario_pes,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.fl_status_rep') AS fl_status_rep,
        TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_repasse_rep')) AS dt_repasse_rep,
        lake_mirror.synced_at AS ts_synced
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'PAYOUT'
)
SELECT
    payout_row.id,
    payout_row.id_repasse_rep,
    payout_row.id_contrato_con,
    contrato.codigo_contrato,
    payout_row.id_recebimento_recb,
    cobranca.id_sacado_sac,
    payout_row.id_locatario_pes,
    locatario.nome_pes,
    payout_row.fl_status_rep,
    payout_row.dt_repasse_rep,
    payout_row.ts_synced
FROM
    payout_row AS payout_row
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_contrato AS contrato
        ON payout_row.id_contrato_con = contrato.id_contrato_con
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_cobranca AS cobranca
        ON payout_row.id_recebimento_recb = cobranca.id_recebimento_recb
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_locatario AS locatario
        ON payout_row.id_locatario_pes = locatario.id_pessoa_pes
