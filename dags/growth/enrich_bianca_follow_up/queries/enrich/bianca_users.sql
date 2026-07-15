WITH bianca_signal_actions AS (
    -- Signal Jaiminho actions (not follow-up ruleIds). Confirmed vs ConciergeContactSubmissionClassifieds / SEARCH proxy.
    -- A1: greeting with property context → BiancaFollowupVisitSeeker
    SELECT
        'greeting_context' AS trigger_type,
        'BiancaWelcomeContextSeeker_whatsapp_message' AS action
    UNION ALL
    -- A2, D1: generic greeting (no property/filter context) → BiancaFollowupSeeker
    SELECT
        'greeting_generic',
        'BiancaWelcomeSeekerTest_whatsapp_message'
    UNION ALL
    -- D2: greeting with saved search filters → BiancaFollowupFiltersSeeker
    SELECT
        'greeting_filters',
        'BiancaWelcomeFiltersSeeker_whatsapp_message'
    UNION ALL
    -- B1: confirm contact (agency), first-time user → BiancaFollowupVisitConfirmSeeker
    SELECT
        'confirm_contact',
        'BiancaConfirmDataTycSeeker_whatsapp_message'
    UNION ALL
    -- B2: confirm contact (agency), returning user (ToS already accepted) → BiancaFollowupVisitConfirm2Seeker
    SELECT
        'confirm_contact_returning',
        'BiancaConfirmDataSeeker_whatsapp_message'
    UNION ALL
    -- C1, C2: confirm contact (pre-schedule visit) → BiancaFollowupScheduleVisitSeeker
    SELECT
        'confirm_contact_visit',
        'BiancaConfirmDataVisitSeeker_whatsapp_message'
    UNION ALL
    SELECT
        'confirm_contact_visit',
        'BiancaConfirmDataVisitTycSeeker_whatsapp_message'
    UNION ALL
    -- E1: after property recommendations carousel → BiancaFollowupRecSeeker
    SELECT
        'after_recommendations',
        'biancaImovelwebRecsCarousel_whatsapp_message_carousel'
),

conv_tails AS (
    SELECT
        m.id_session,
        m.id AS signal_message_id,
        m.id_external,
        m.role,
        m.ts_created AS tail_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY m.id_session
            ORDER BY m.ts_created DESC
        ) AS rownum
    FROM datalake_copilot_service_clean.message AS m
    WHERE
        m.channel = 'WHATSAPP_BIANCA_CHAT'
        AND DATEDIFF(CURRENT_DATE, DATE(m.ts_created)) <= 60
),

candidates AS (
    SELECT
        un.destination AS phone_number,
        bsa.trigger_type,
        ct.id_session,
        ct.signal_message_id,
        ct.tail_timestamp AS signal_timestamp,
        MD5(CONCAT(un.destination, '|', bsa.trigger_type, '|', CAST(ct.tail_timestamp AS STRING))) AS id,
        CURRENT_TIMESTAMP() AS created_at,
        YEAR(CURRENT_DATE()) AS year,
        MONTH(CURRENT_DATE()) AS month,
        DAY(CURRENT_DATE()) AS day,
        NULLIF(GET_JSON_OBJECT(un.payload, '$.templateVariables.1'), '') AS filter_param
    FROM datalake_jaiminho_clean.user_notifications AS un
    INNER JOIN conv_tails AS ct
        ON un.id_entity = ct.id_external
    INNER JOIN bianca_signal_actions AS bsa
        ON un.action = bsa.action
    WHERE
        UPPER(un.channel) = 'WHATSAPP'
        AND UPPER(un.status) IN ('READ', 'SENT', 'DELIVERED')
        AND DATEDIFF(CURRENT_DATE, MAKE_DATE(un.year, un.month, un.day)) <= 4
        AND un.destination IS NOT NULL
        AND ct.id_session IS NOT NULL
        AND ct.rownum = 1
        AND ct.role IN ('AI', 'HARDCODED')
        AND ct.tail_timestamp <= CURRENT_TIMESTAMP() - INTERVAL 24 HOURS
)

SELECT
    id,
    phone_number,
    trigger_type,
    id_session,
    signal_message_id,
    signal_timestamp,
    created_at,
    year,
    month,
    day,
    CASE WHEN trigger_type = 'greeting_filters' THEN filter_param END AS filters_applied
FROM candidates
