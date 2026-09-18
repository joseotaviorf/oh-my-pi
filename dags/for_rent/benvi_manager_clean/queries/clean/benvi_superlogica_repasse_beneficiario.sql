-- Nested PAYOUT.payload.proprietarios_beneficiarios. Not a Superlogica HTTP extractor.
WITH payout_row AS (
    SELECT
        lake_mirror.id,
        lake_mirror.vendor_natural_key AS id_repasse_rep,
        lake_mirror.synced_at AS ts_synced,
        FROM_JSON(
            get_json_object(CAST(lake_mirror.payload AS STRING), '$.proprietarios_beneficiarios'),
            'array<map<string,string>>'
        ) AS proprietarios_beneficiarios
    FROM
        datalake_benvi_manager_raw.lake_mirror AS lake_mirror
    WHERE
        lake_mirror.resource_code = 'PAYOUT'
)
SELECT
    payout_row.id,
    payout_row.id_repasse_rep,
    CAST(beneficiario.nr_item AS INT) + 1 AS nr_item,
    beneficiario.item_map['id_pessoa_pes'] AS id_pessoa_pes,
    beneficiario.item_map['nm_fracao'] AS nm_fracao,
    TO_JSON(beneficiario.item_map) AS item_payload,
    payout_row.ts_synced
FROM
    payout_row AS payout_row
LATERAL VIEW POSEXPLODE(payout_row.proprietarios_beneficiarios) beneficiario AS nr_item, item_map
