WITH status AS (
    SELECT DISTINCT
        ia.id_inspection,
        ia.status,
        ia.ts_updated
    FROM
        datalake_inspection_services_clean.inspection_aud AS ia
),
pivot_status AS (
    SELECT
        *
    FROM
        status
    PIVOT (
        MAX(ts_updated) FOR status IN (
            "scheduled",
            "pending_appointment",
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
            "reviewed",
            -- "finished" -- Legado
            "automatic_repair_processing", --Offboarding
            "budget_approval", -- Offboarding
            "budget_approval_sent_to_owner", -- Offboarding
            "budget_approval_sent_to_tenant", -- Offboarding
            "budget_approval_started_by_owner", -- Offboarding
            "budget_approval_started_by_tenant", --Offboarding
            "contestation_analysis_finished", -- Offboarding
            "sent_to_inspection_editing" -- Offboarding

        )
    )
)
SELECT
    id_inspection,
    pending_appointment AS ts_pending_appointment,
    scheduled AS ts_scheduled,
    received AS ts_received,
    processing AS ts_processing,
    cancelled AS ts_cancelled,
    sent_to_review AS ts_sent_to_review,
    review_started AS ts_review_started,
    sent_to_inspection_editing AS ts_sent_to_inspection_editing,
    automatic_repair_processing AS ts_automatic_repair_processing,
    sent_to_repair_analysis AS ts_sent_to_repair_analysis,
    sent_to_owner_review AS ts_sent_to_owner_review,
    review_started_by_owner AS ts_review_started_by_owner,
    sent_to_tenant_review AS ts_sent_to_tenant_review,
    review_started_by_tenant AS ts_review_started_by_tenant,
    sent_to_contestation_analysis AS ts_sent_to_contestation_analysis,
    contestation_analysis_finished AS ts_contestation_analysis_finished,
    budget_approval AS ts_budget_approval,
    budget_approval_sent_to_owner AS ts_budget_approval_sent_to_owner,
    budget_approval_started_by_owner AS ts_budget_approval_started_by_owner,
    budget_approval_sent_to_tenant AS ts_budget_approval_sent_to_tenant,
    budget_approval_started_by_tenant AS ts_budget_approval_started_by_tenant,
    reviewed AS ts_reviewed,
    NOW() AS ts_load
FROM
    pivot_status
