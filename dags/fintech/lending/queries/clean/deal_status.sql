SELECT
    id,
    deal_id AS id_deal,
    status,
    created_at AS ts_created
FROM
    datalake_lending_raw.deal_status
