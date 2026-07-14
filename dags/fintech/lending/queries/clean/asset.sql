SELECT
    id,
    deal_id AS id_deal,
    external_id AS id_external,
    asset_type,
    snapshot_payload,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.asset
