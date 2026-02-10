WITH hightouch_all_data AS (
    SELECT
        jlog.row_instance_id AS id_row_instance,
        jlog.row_id AS id_row,
        COALESCE(get_json_object(schan.fields, '$.id_user'), jlog.row_id) AS id_user,
        COALESCE(get_json_object(schan.fields, '$.id_house_338aa0')) AS id_house,
        COALESCE(get_json_object(schan.fields, '$.id_rent_flow_584f65')) AS id_rent_flow,
        schan.sync_id AS id_sync,
        schan.sync_run_id AS id_sync_run,
        CASE jmeta.node_name
            WHEN 'Control - Send to destination' THEN 'Control'
            WHEN 'Jaiminho - Send to destination' THEN 'Test'
        END AS group_name,
        jlog.timestamp,
        sruns.started_at,
        sruns.finished_at
    FROM
        hightouch_planner.journey_log_1fff99f76153459ca49595e7d9492bd8 AS jlog
    LEFT JOIN
        hightouch_planner.journey_metadata_1fff99f76153459ca49595e7d9492bd8 AS jmeta
        ON jlog.to_node_id = jmeta.node_id
    INNER JOIN
        hightouch_audit.sync_changelog AS schan
        ON jlog.row_instance_id = schan.row_id
    INNER JOIN
        hightouch_audit.sync_runs AS sruns
        ON schan.sync_run_id = sruns.sync_run_id
    WHERE
        jmeta.node_name IN ('Jaiminho - Send to destination', 'Control - Send to destination')
        AND schan.op_type = 'added'
        AND schan.status = 'succeeded'
        AND schan.sync_id IN (2676210, 2676209)
        AND sruns.sync_id IN (2676210, 2676209)
),
rn_count AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY IF(group_name = 'Test', 1, 2)) AS rn_latest
    FROM
        hightouch_all_data
)
SELECT
    rnc.id_row_instance,
    rnc.id_row,
    rnc.id_user,
    rnc.id_house,
    rnc.id_rent_flow,
    rnc.id_sync,
    rnc.id_sync_run,
    rnc.group_name,
    rnc.timestamp,
    rnc.started_at,
    rnc.finished_at
FROM
    rn_count AS rnc
WHERE
    rnc.rn_latest = 1
    AND rnc.id_house is NOT NULL
