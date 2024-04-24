SELECT
    id,
    content_id AS id_content,
    action_id AS id_action,
    rule_type,
    order,
    name,
    journey_version,
    test_identifier,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_journey_flow_raw.rule
