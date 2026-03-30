SELECT
    id,
    house_id AS id_house,
    business_context,
    status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day    
FROM
    datalake_big_agent_raw.listing