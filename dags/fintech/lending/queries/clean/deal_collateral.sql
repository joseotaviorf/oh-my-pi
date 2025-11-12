SELECT 
    id,
    deal_id AS id_deal,
    external_id AS id_external,
    effective_date AS dt_effective,
    value,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_lending_raw.deal_collateral