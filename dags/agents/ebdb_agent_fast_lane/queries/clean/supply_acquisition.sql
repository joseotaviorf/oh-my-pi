-- Clean layer for EBDB SupplyAcquisition (ebdb_agent_fast_lane DAG).
SELECT
    id,
    agent_uuid AS uuid_agent,
    property_id AS id_property,
    status,
    start_datetime AS ts_start,
    end_datetime AS ts_end,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.SupplyAcquisition
