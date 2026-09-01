SELECT
    id,
    development_id AS id_development,
    visit_id AS id_visit,
    demand_id AS id_demand,
    agent_id AS id_agent,
    event_id AS uuid_event,
    actor,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.DevelopmentNegotiation
