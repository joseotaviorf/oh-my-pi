WITH deduplicated_rules AS (
    SELECT
        rule_id AS id_rule,
        action_id AS id_action,
        status AS status,
        business_context AS business_context,
        category AS category,
        company AS company,
        context AS context,
        cost_center AS cost_center,
        journey_step AS journey_step,
        line AS line,
        rule_profile AS rule_profile,
        team AS team,
        notification_type AS notification_type,
        action_profile AS action_profile,
        reason AS reason,
        deep_link AS deep_link,
        subject_template AS subject_template,
        body_template AS body_template,
        body_template_path AS body_template_path,
        subject_content AS subject_content,
        body_content AS body_content,
        CAST(generated_at AS TIMESTAMP) AS ts_export_generated,
        CAST(NULL AS TIMESTAMP) AS ts_updated,
        CAST(NULL AS TIMESTAMP) AS ts_created,
        year,
        month,
        day,
        -- Use ROW_NUMBER to handle duplicates, keeping the most recent record
        ROW_NUMBER() OVER (
            PARTITION BY rule_id, action_id
            ORDER BY generated_at DESC, year DESC, month DESC, day DESC
        ) as rn
    FROM
        datalake_comms_manager_raw.comms_manager_rules
)
SELECT
    id_rule,
    id_action,
    status,
    business_context,
    category,
    company,
    context,
    cost_center,
    journey_step,
    line,
    rule_profile,
    team,
    notification_type,
    action_profile,
    reason,
    deep_link,
    subject_template,
    body_template,
    body_template_path,
    subject_content,
    body_content,
    ts_export_generated,
    ts_updated,
    ts_created,
    year,
    month,
    day
FROM deduplicated_rules
WHERE rn = 1
