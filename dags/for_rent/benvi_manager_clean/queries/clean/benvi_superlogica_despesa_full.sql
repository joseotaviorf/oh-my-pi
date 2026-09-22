-- Derived parity projection for the RAW despesas_full spreadsheet tab.
-- Its 12 columns are names the extraction script invents over the union of
-- CONTRACT_EXPENSE and VACANT_PROPERTY_EXPENSE, so they are reproduced here rather
-- than read from a vendor key. Labels and fallback order follow build_despesas_full.
-- A recurring template is kept once per template id and only from CONTRACT_EXPENSE;
-- a one off launch is kept once per launch id and only from VACANT_PROPERTY_EXPENSE,
-- which is exactly how build_despesas_full splits its two inputs.
WITH expense_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_lancamento_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_lancamento_imodm') AS id_lancamento_imodm,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recorrencia') AS id_recorrencia,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_descricao_prd') AS st_descricao_prd,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_descricao') AS st_descricao,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_produto_prd') AS id_produto_prd,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_produto') AS id_produto,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.vl_valor_imod') AS vl_valor_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.vl_valor_imodm') AS vl_valor_imodm,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.valor') AS valor,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_debito_imod') AS id_debito_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_debito_imodm') AS id_debito_imodm,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_credito_imod') AS id_credito_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_credito_imodm') AS id_credito_imodm,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_observacao_imod') AS st_observacao_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_observacao_imodm') AS st_observacao_imodm,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_complemento_imod') AS st_complemento_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.st_complemento_imodm') AS st_complemento_imodm,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.complemento') AS complemento,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.competencia') AS competencia,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_competencia_imod') AS dt_competencia_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_referencia_imod') AS dt_referencia_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_lancamento_imod') AS dt_lancamento_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_imovel_imo') AS id_imovel_imo,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.fl_status_imod') AS fl_status_imod,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.fl_status_imodm') AS fl_status_imodm,
        lake_mirror.synced_at,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(
                NULLIF(get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_lancamento_imodm'), ''),
                NULLIF(get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recorrencia'), ''),
                lake_mirror.vendor_natural_key
            )
            ORDER BY
                CASE lake_mirror.resource_code
                    WHEN 'CONTRACT_EXPENSE' THEN 0
                    ELSE 1
                END,
                lake_mirror.id
        ) AS rn
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        (
            lake_mirror.resource_code = 'CONTRACT_EXPENSE'
            AND COALESCE(
                NULLIF(get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_lancamento_imodm'), ''),
                NULLIF(get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recorrencia'), '')
            ) IS NOT NULL
        )
        OR (
            lake_mirror.resource_code = 'VACANT_PROPERTY_EXPENSE'
            AND COALESCE(
                NULLIF(get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_lancamento_imodm'), ''),
                NULLIF(get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recorrencia'), '')
            ) IS NULL
        )
)
SELECT
    expense_row.id,
    expense_row.id_lancamento_imod,
    COALESCE(
        NULLIF(expense_row.id_lancamento_imodm, ''),
        NULLIF(expense_row.id_recorrencia, ''),
        expense_row.id_lancamento_imod
    ) AS id_despesa,
    CASE
        WHEN COALESCE(NULLIF(expense_row.id_lancamento_imodm, ''), NULLIF(expense_row.id_recorrencia, '')) IS NOT NULL
            THEN 'recorrente'
        ELSE 'avulsa'
    END AS tipo_registro,
    COALESCE(
        NULLIF(expense_row.st_descricao_prd, ''),
        NULLIF(expense_row.st_descricao, ''),
        NULLIF(expense_row.id_produto_prd, ''),
        expense_row.id_produto
    ) AS tipo,
    CAST(
        COALESCE(
            NULLIF(expense_row.vl_valor_imod, ''),
            NULLIF(expense_row.vl_valor_imodm, ''),
            expense_row.valor
        ) AS DOUBLE
    ) AS valor,
    CASE COALESCE(NULLIF(expense_row.id_debito_imod, ''), expense_row.id_debito_imodm)
        WHEN '1' THEN 'Proprietário'
        WHEN '2' THEN 'Inquilino'
        WHEN '3' THEN 'Imobiliária/Terceiro'
        ELSE COALESCE(NULLIF(expense_row.id_debito_imod, ''), expense_row.id_debito_imodm)
    END AS quem_paga,
    CASE COALESCE(NULLIF(expense_row.id_credito_imod, ''), expense_row.id_credito_imodm)
        WHEN '1' THEN 'Proprietário'
        WHEN '2' THEN 'Inquilino'
        WHEN '3' THEN 'Imobiliária/Terceiro'
        ELSE COALESCE(NULLIF(expense_row.id_credito_imod, ''), expense_row.id_credito_imodm)
    END AS quem_recebe,
    COALESCE(
        NULLIF(expense_row.st_observacao_imod, ''),
        NULLIF(expense_row.st_observacao_imodm, ''),
        NULLIF(expense_row.st_complemento_imod, ''),
        NULLIF(expense_row.st_complemento_imodm, ''),
        expense_row.complemento
    ) AS observacao,
    CASE
        WHEN COALESCE(NULLIF(expense_row.id_lancamento_imodm, ''), NULLIF(expense_row.id_recorrencia, '')) IS NOT NULL
            THEN 'recorrente'
        ELSE COALESCE(
            NULLIF(expense_row.competencia, ''),
            NULLIF(expense_row.dt_competencia_imod, ''),
            NULLIF(expense_row.dt_referencia_imod, ''),
            expense_row.dt_lancamento_imod
        )
    END AS competencia,
    COALESCE(NULLIF(expense_row.id_produto_prd, ''), expense_row.id_produto) AS id_produto,
    expense_row.id_contrato_con AS id_contrato,
    expense_row.id_imovel_imo AS id_imovel,
    COALESCE(NULLIF(expense_row.fl_status_imod, ''), expense_row.fl_status_imodm) AS status,
    expense_row.synced_at AS ts_synced
FROM
    expense_row AS expense_row
WHERE
    expense_row.rn = 1
