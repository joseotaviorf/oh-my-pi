SELECT
    BIGINT(id) AS id,
    BIGINT(house_id) AS id_house,
    BIGINT(agent_id) AS id_agent,
    bonus_fee,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_nazare_raw.supply_acquisition_share
