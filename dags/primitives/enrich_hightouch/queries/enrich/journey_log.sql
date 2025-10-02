SELECT
    CAST(row_id AS STRING) AS id_row,
    CAST(row_instance_id AS STRING) AS id_row_instance,
    CAST(run_id AS STRING) AS id_run,
    CAST(journey_id AS STRING) AS id_journey,
    CAST(from_node_id AS STRING) AS id_from_node,
    CAST(to_node_id AS STRING) AS id_to_node,
    CAST(event_type AS STRING) AS event_type,
    CAST(source_table AS STRING) AS source_table,
    CAST(timestamp AS TIMESTAMP) AS ts_event
FROM
    hightouch_audit.journey_log_view_quinto_production
