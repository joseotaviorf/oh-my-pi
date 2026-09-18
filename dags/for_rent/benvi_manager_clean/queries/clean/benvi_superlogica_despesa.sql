-- UNION of CONTRACT_EXPENSE (GET /despesas) and VACANT_PROPERTY_EXPENSE (GET /imoveisdespesa).
-- Same launch id keeps the CONTRACT_EXPENSE row.
WITH expense_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_lancamento_imod,
        lake_mirror.resource_code,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_imovel_imo') AS id_imovel_imo,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_contrato_con') AS id_contrato_con,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_recebimento_recb') AS id_recebimento_recb,
        get_json_object(CAST(lake_mirror.payload AS STRING), '$.id_repasse_rep') AS id_repasse_rep,
        CAST(get_json_object(CAST(lake_mirror.payload AS STRING), '$.vl_valor_imod') AS DOUBLE) AS vl_valor_imod,
        TO_DATE(get_json_object(CAST(lake_mirror.payload AS STRING), '$.dt_lancamento_imod')) AS dt_lancamento_imod,
        lake_mirror.synced_at AS ts_synced,
        ROW_NUMBER() OVER (
            PARTITION BY lake_mirror.vendor_natural_key
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
        lake_mirror.resource_code IN ('CONTRACT_EXPENSE', 'VACANT_PROPERTY_EXPENSE')
)
SELECT
    expense_row.id,
    expense_row.id_lancamento_imod,
    expense_row.id_imovel_imo,
    expense_row.id_contrato_con,
    expense_row.id_recebimento_recb,
    expense_row.id_repasse_rep,
    expense_row.resource_code,
    expense_row.vl_valor_imod,
    expense_row.dt_lancamento_imod,
    expense_row.ts_synced
FROM
    expense_row AS expense_row
WHERE
    expense_row.rn = 1
