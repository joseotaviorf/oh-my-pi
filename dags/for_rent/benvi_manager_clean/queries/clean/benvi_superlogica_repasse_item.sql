-- Nested PAYOUT.payload.repasse_item. Not a Superlogica HTTP extractor.
WITH payout_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_repasse_rep,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.repasse_item'),
            'array<map<string,string>>'
        ) AS repasse_item
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'PAYOUT'
)
SELECT
    payout_row.id,
    payout_row.id_repasse_rep,
    CAST(item_row.nr_item AS INT) + 1 AS nr_item,
    item_row.item_map['id_recebimento_recb'] AS id_recebimento_recb,
    item_row.item_map['vl_repasse'] AS vl_repasse,
    TO_JSON(item_row.item_map) AS item_payload,
    payout_row.ts_synced
FROM
    payout_row AS payout_row
LATERAL VIEW POSEXPLODE(payout_row.repasse_item) item_row AS nr_item, item_map
