SELECT
    CAST(journey_id AS STRING) AS id_journey,
    CAST(node_id AS STRING) AS id_node,
    CAST(to_node_id AS ARRAY<STRING>) AS id_to_node,
    CAST(journey_name AS STRING) AS journey_name,
    CAST(node_name AS STRING) AS node_name,
    CAST(node_type AS STRING) AS node_type,
    CAST(source_table AS STRING) AS source_table,

FROM
    hightouch_audit.journey_metadata_view_quinto_production
