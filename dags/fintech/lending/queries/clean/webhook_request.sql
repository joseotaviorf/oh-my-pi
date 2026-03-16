SELECT
    id,
    deal_uuid AS uuid_deal,
    payload,
    status,
    type,
    source,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.webhook_request
