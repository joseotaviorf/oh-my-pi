SELECT
    id,
    repair_request_item_id AS id_repair_request_item,
    asset_url,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_repairs_raw.repair_evidence
