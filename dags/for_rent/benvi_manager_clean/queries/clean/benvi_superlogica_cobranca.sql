-- PII: st_nome_sac, st_cgc_sac, st_email_sac, and address fields.
-- Join CHARGE.id_sacado_sac to locatario.id_sacado_sac (not locatario.id_pessoa_pes).
-- Join CHARGE.id_contrato_con to contrato.id_contrato_con.
WITH charge_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_recebimento_recb,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_sacado_sac') AS id_sacado_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.fl_status_recb') AS fl_status_recb,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_nome_sac') AS st_nome_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_cgc_sac') AS st_cgc_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_email_sac') AS st_email_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_endereco_sac') AS st_endereco_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_numero_sac') AS st_numero_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_complemento_sac') AS st_complemento_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_bairro_sac') AS st_bairro_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_cidade_sac') AS st_cidade_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_estado_sac') AS st_estado_sac,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_cep_sac') AS st_cep_sac,
        TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_vencimento_recb')) AS dt_vencimento_recb,
        TO_DATE(
            COALESCE(
                get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_liquidacao_recb'),
                get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_recebimento_recb')
            )
        ) AS dt_liquidacao_recb,
        lake_mirror.synced_at AS ts_synced
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'CHARGE'
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
    charge_row.id,
    charge_row.id_recebimento_recb,
    charge_row.id_sacado_sac,
    tenant_by_sacado.id_pessoa_pes,
    charge_row.id_contrato_con,
    contrato.codigo_contrato,
    charge_row.fl_status_recb,
    charge_row.st_nome_sac,
    charge_row.st_cgc_sac,
    charge_row.st_email_sac,
    charge_row.st_endereco_sac,
    charge_row.st_numero_sac,
    charge_row.st_complemento_sac,
    charge_row.st_bairro_sac,
    charge_row.st_cidade_sac,
    charge_row.st_estado_sac,
    charge_row.st_cep_sac,
    charge_row.dt_vencimento_recb,
    charge_row.dt_liquidacao_recb,
    charge_row.ts_synced
FROM
    charge_row AS charge_row
LEFT JOIN
    tenant_by_sacado AS tenant_by_sacado
        ON charge_row.id_sacado_sac = tenant_by_sacado.id_sacado_sac
        AND tenant_by_sacado.rn = 1
LEFT JOIN
    datalake_benvi_manager_clean.benvi_superlogica_contrato AS contrato
        ON charge_row.id_contrato_con = contrato.id_contrato_con
