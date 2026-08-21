-- sk_analyst is the unified analyst key. Today it is the Salesforce User Id;
-- when Twilio identity is available, switch to COALESCE(id_analyst, id_twillio).
SELECT
    id_event AS sk_event,
    COALESCE(id_analyst, CAST(-1 AS STRING)) AS sk_analyst,
    id_analyst AS sk_salesforce,
    CAST(-1 AS STRING) AS sk_twillio,
    id_event_type AS sk_event_type,
    id_manager AS sk_manager,
    CASE
        WHEN id_analyst IS NOT NULL THEN 'salesforce'
        ELSE 'twilio'
    END AS sk_id_type,
    username,
    email,
    alias,
    operations,
    bpo,
    is_active,
    is_partner,
    is_deleted,
    _is_current AS is_current,
    created_date AS ts_created,
    committed_at AS ts_committed,
    _effective_timestamp AS ts_effective,
    _expired_timestamp AS ts_expired,
    NOW() AS ts_load
FROM
    core_support_journey.analyst
WHERE
    _last_updated_at >= '{load_start_date}'
    AND _last_updated_at < '{load_end_date}'
