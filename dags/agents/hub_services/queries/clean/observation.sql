SELECT
    id,
    visitor_id AS id_visitor,
    creator_id AS id_creator,
    version,
    value,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.observation
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
