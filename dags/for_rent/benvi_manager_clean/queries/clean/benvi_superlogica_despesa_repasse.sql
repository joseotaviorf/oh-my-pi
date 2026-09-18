-- Nested CONTRACT_EXPENSE.payload.repasses. Not a Superlogica HTTP extractor.
WITH expense_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_lancamento_imod,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.repasses'),
            'array<map<string,string>>'
        ) AS repasses
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'CONTRACT_EXPENSE'
)
SELECT
    expense_row.id,
    expense_row.id_lancamento_imod,
    CAST(repasse_nested.nr_item AS INT) + 1 AS nr_item,
    repasse_nested.item_map['id_repasse_rep'] AS id_repasse_rep,
    TO_JSON(repasse_nested.item_map) AS item_payload,
    expense_row.ts_synced
FROM
    expense_row AS expense_row
LATERAL VIEW POSEXPLODE(expense_row.repasses) repasse_nested AS nr_item, item_map
