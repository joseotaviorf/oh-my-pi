SELECT
    id,
    house_id AS id_house,
    actor_identifier AS id_actor,
    business_context,
    actor_type,
    actor_role,
    on_behalf_of,
    channel,
    event_type,
    journey,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.HouseEventLog
