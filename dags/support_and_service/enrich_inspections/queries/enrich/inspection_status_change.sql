WITH status AS (
    SELECT DISTINCT
        ia.id_inspection,
        ia.status,
        ia.ts_updated AS ts_updated
    FROM
        datalake_inspections_clean.inspection_aud AS ia
),
pivot_status AS (
    SELECT
        *
    FROM
        status 
    PIVOT (
        MAX(ts_updated) FOR status IN (
            "scheduled",
            "received",
            "processing",
            "cancelled",
            -- "inspected", -- Legado
            "sent_to_review", -- Onboarding
            "review_started", -- Onboarding
            -- "sent_to_analysis", -- Legado
            "sent_to_repair_analysis", -- Offboarding
            "sent_to_owner_review", -- Offboarding
            "review_started_by_owner", -- Offboarding
            "sent_to_tenant_review", -- Offboarding
            "review_started_by_tenant", -- Offboarding
            "sent_to_contestation_analysis", -- Offboarding
            "reviewed"
            -- "finished" -- Legado
        )
    )
)
SELECT
    id_inspection,
    scheduled AS ts_scheduled,
    received AS ts_received,
    processing AS ts_processing,
    cancelled AS ts_cancelled,
    sent_to_review AS ts_sent_to_review,
    review_started AS ts_review_started,
    sent_to_repair_analysis AS ts_sent_to_repair_analysis,
    sent_to_owner_review AS ts_sent_to_owner_review,
    review_started_by_owner AS ts_review_started_by_owner,
    sent_to_tenant_review AS ts_sent_to_tenant_review,
    review_started_by_tenant AS ts_review_started_by_tenant,
    sent_to_contestation_analysis AS ts_sent_to_contestation_analysis,
    reviewed AS ts_reviewed,
    NOW() AS ts_load
FROM
    pivot_status