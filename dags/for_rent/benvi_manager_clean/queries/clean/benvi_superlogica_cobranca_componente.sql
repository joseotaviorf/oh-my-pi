-- Nested CHARGE.payload.compo_recebimento. Not a Superlogica HTTP extractor.
WITH charge_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_recebimento_recb,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.compo_recebimento'),
            'array<map<string,string>>'
        ) AS composicao
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'CHARGE'
)
SELECT
    charge_row.id,
    charge_row.id_recebimento_recb,
    CAST(componente.nr_item AS INT) + 1 AS nr_item,
    componente.item_map['id_produto_prd'] AS id_produto_prd,
    componente.item_map['st_descricao'] AS st_descricao,
    componente.item_map['vl_valor'] AS vl_valor,
    TO_JSON(componente.item_map) AS item_payload,
    charge_row.ts_synced
FROM
    charge_row AS charge_row
LATERAL VIEW POSEXPLODE(charge_row.composicao) componente AS nr_item, item_map
