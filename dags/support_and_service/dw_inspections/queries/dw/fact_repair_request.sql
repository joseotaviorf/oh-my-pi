WITH repair_request_media AS (
    SELECT
        orm.id_origin AS id_repair_request,
        COUNT(DISTINCT orm.id_media) AS total_media
    FROM
        datalake_inspections.report_review_media AS orm
    WHERE
        origin = "repair_request"
    GROUP BY 1
)
SELECT DISTINCT
    rr.id_repair_request AS sk_repair_request,
    rr.id_inspection AS sk_inspection,
    rr.id_contract AS sk_contract,
    rr.id_contestation AS sk_contestation,
    rr.id_item_group AS sk_item_group,
    rr.id_room AS sk_room,
    rr.id_assessment AS sk_assessment,
    rr.id_requester AS sk_requester,
    rr.id_granted_by AS sk_granted_by,
    rr.id_contestation_requester AS sk_contestation_requester,
    rr.total_tenant_contestation,
    rr.total_tenant_budget_approval_contestation,
    rr.total_owner_budget_approval_contestation,
    COALESCE(rrm.total_media, 0) <> 0 AS has_media,
    COALESCE(rr.total_tenant_contestation, 0) <> 0 AS has_tenant_contestation,
    COALESCE(rr.total_tenant_budget_approval_contestation, 0) <> 0 AS has_tenant_budget_approval_contestation,
    COALESCE(rr.total_owner_budget_approval_contestation, 0) <> 0 AS has_owner_budget_approval_contestation,
    rr.is_cost_absorbed_by_company,
    rr.is_cost_absorbed_by_tenant,
    rr.is_cost_absorbed_by_owner,
    rr.is_exempted,
    rr.is_exempted_by_owner_from_budget,
    rr.is_exempted_by_owner,
    rr.is_requested_by_owner,
    rr.is_finished,
    rr.has_automatically_identified,
    rr.has_automatic_identification_accepted,
    rr.ts_granted,
    rr.ts_created,
    rr.ts_updated,
    NOW() AS ts_load,
    rr.year,
    rr.month,
    rr.day
FROM
    datalake_inspections.repair_request AS rr
LEFT JOIN
    repair_request_media AS rrm
        ON rrm.id_repair_request = rr.id_repair_request
