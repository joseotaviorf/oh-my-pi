-- Nested CONTRACT_EXPENSE.payload.movimentacoes. Not a Superlogica HTTP extractor.
WITH expense_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_lancamento_imod,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.movimentacoes'),
            'array<map<string,string>>'
        ) AS movimentacoes
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'CONTRACT_EXPENSE'
)
SELECT
    expense_row.id,
    expense_row.id_lancamento_imod,
    CAST(movimento.nr_item AS INT) + 1 AS nr_item,
    movimento.item_map['id_movimentacao_mov'] AS id_movimentacao_mov,
    movimento.item_map['id_recebimento_recb'] AS id_recebimento_recb,
    movimento.item_map['fl_status_mov'] AS fl_status_mov,
    movimento.item_map['vl_valor_mov'] AS vl_valor_mov,
    TO_JSON(movimento.item_map) AS item_payload,
    expense_row.ts_synced
FROM
    expense_row AS expense_row
LATERAL VIEW POSEXPLODE(expense_row.movimentacoes) movimento AS nr_item, item_map
