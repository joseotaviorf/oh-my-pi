SELECT
    id,
    house_id AS id_house,
    agent_id AS id_agent,
    bonus_fee,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_nazare_raw.supply_acquisition_share
