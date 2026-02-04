WITH hightouch_all_data AS (
    SELECT
        jlog.row_instance_id AS id_row_instance,
        jlog.row_id AS id_row,
        COALESCE(get_json_object(schan.fields, '$.id_user'), jlog.row_id) AS id_user,
        COALESCE(get_json_object(schan.fields, '$.id_proposal_931d6c'),
                 get_json_object(schan.fields, '$.id_proposal_c4a188') ) AS id_proposal,
        get_json_object(schan.fields, '$.party_rejection_reasons_80ff5f') AS rejection_reason,
        schan.sync_id AS id_sync,
        schan.sync_run_id AS id_sync_run,
        CASE jmeta.node_name
            WHEN 'AUDIT CONTROL' THEN 'Control'
            WHEN 'Send to destination' THEN 'Test'
        END AS group_name,
        jlog.timestamp,
        sruns.started_at,
        sruns.finished_at
    FROM
        hightouch_planner.journey_log_83b9e284127644299f5b4fe9c292e826 AS jlog
    LEFT JOIN
        hightouch_planner.journey_metadata_83b9e284127644299f5b4fe9c292e826 AS jmeta
        ON jlog.to_node_id = jmeta.node_id
    INNER JOIN
        hightouch_audit.sync_changelog AS schan
        ON jlog.row_instance_id = schan.row_id
    INNER JOIN
        hightouch_audit.sync_runs AS sruns
        ON schan.sync_run_id = sruns.sync_run_id
    WHERE
        jmeta.node_name IN ('AUDIT CONTROL', 'Send to destination')
        AND schan.op_type = 'added'
        AND schan.status = 'succeeded'
        AND schan.sync_id IN (2666486, 2666290)
        AND sruns.sync_id IN (2666486, 2666290)
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
    rnc.id_proposal,
    rnc.rejection_reason,
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
