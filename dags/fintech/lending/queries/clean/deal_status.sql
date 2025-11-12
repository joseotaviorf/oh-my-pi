SELECT
    id,
    deal_id AS id_deal,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_lending_raw.deal_status