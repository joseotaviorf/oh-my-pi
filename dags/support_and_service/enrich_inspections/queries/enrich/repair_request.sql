WITH total_contestations AS (
    SELECT
        id_repair_request,
        COUNT(CASE WHEN reviewer_type = 'TENANT' AND (origin = 'REVIEW' OR origin IS NULL) THEN 1 END) AS total_tenant_contestation,
        COUNT(CASE WHEN reviewer_type = 'TENANT' AND origin = 'BUDGET_APPROVAL' THEN 1 END) AS total_tenant_budget_approval_contestation,
        COUNT(CASE WHEN reviewer_type = 'OWNER' AND origin = 'BUDGET_APPROVAL' THEN 1 END) AS total_owner_budget_approval_contestation
    FROM
        datalake_inspections_clean.contestation AS c
    LEFT JOIN
        datalake_inspections_clean.reviewer AS r
          ON r.id_reviewer = c.id_reviewer
    GROUP BY 1
),
repair_request_media AS (
    SELECT
        orm.id_origin AS id_repair_request,
        COUNT(DISTINCT orm.id_media) AS total_media
    FROM
        datalake_inspections.report_review_media AS orm
    WHERE
        origin = "repair_request"
    GROUP BY 1
)
SELECT
    rr.id_repair_request,
    ins.id_inspection,
    ins.id_contract,
    c.id_contestation,
    rr.id_item_group,
    ro.id_room,
    asm.id_assessment,
    rr.id_reviewer AS id_requester,
    rr.id_granted_by,
    c.id_reviewer AS id_contestation_requester,
    rev1.reviewer_type AS requester_type,
    rev2.reviewer_type AS granted_type,
    rr.responsibility,
    rr.type AS repair_type,
    rr.type,
    rr.cost,
    rr.repair_service,
    rr.comment,
    rrm.total_media,
    tc.total_tenant_contestation,
    tc.total_tenant_budget_approval_contestation,
    tc.total_owner_budget_approval_contestation,
    rr.has_automatically_identified,
    rr.has_automatic_identification_accepted,
    CASE
        WHEN rr.responsibility = "ABSORBED_BY_COMPANY" THEN TRUE
        WHEN rr.is_exempted IS TRUE OR rr.responsibility <> "ABSORBED_BY_COMPANY" THEN FALSE
    END AS is_cost_absorbed_by_company,
    CASE
        WHEN rr.responsibility = "TENANT" THEN TRUE
        WHEN rr.is_exempted IS TRUE OR rr.responsibility <> "TENANT" THEN FALSE
    END AS is_cost_absorbed_by_tenant,
    CASE
        WHEN rr.is_exempted IS TRUE OR rr.responsibility = "OWNER" THEN TRUE
        WHEN rr.is_exempted IS FALSE OR rr.responsibility <> "OWNER" THEN FALSE
    END AS is_cost_absorbed_by_owner,
    rr.is_finished,
    rr.is_exempted,
    rr.is_exempted_from_budget AS is_exempted_by_owner_from_budget,
    rev1.reviewer_type = "OWNER" AS is_requested_by_owner,
    rev2.reviewer_type = 'OWNER' AS is_exempted_by_owner,
    CASE
      WHEN rr.is_finished = false AND rev2.reviewer_type = 'ADMIN' AND rr.is_exempted = true THEN true
      ELSE false
    END AS exempted_on_ar,
    rr.ts_created,
    rr.ts_updated,
    rr.ts_granted,
    rr.year,
    rr.month,
    rr.day
FROM
    datalake_inspections_clean.repair_request AS rr
LEFT JOIN
    datalake_inspections_clean.item_group AS ig
      ON rr.id_item_group = ig.id_item_group
LEFT JOIN
    datalake_inspections_clean.room AS ro
      ON ro.id_room = ig.id_room
LEFT JOIN
    datalake_inspections_clean.assessment AS asm
      ON asm.id_assessment = ro.id_assessment
LEFT JOIN
    datalake_inspections_clean.inspection AS ins
      ON ins.id_inspection = asm.id_inspection
LEFT JOIN
    datalake_inspections_clean.reviewer AS rev1
      ON rev1.id_reviewer = rr.id_reviewer
LEFT JOIN
    datalake_inspections_clean.reviewer AS rev2
      ON rev2.id_reviewer = rr.id_granted_by
LEFT JOIN
    total_contestations AS tc
      ON tc.id_repair_request = rr.id_repair_request
LEFT JOIN
    datalake_inspections_clean.contestation AS c
      ON rr.id_repair_request = c.id_repair_request
LEFT JOIN
    repair_request_media AS rrm
      ON rr.id_repair_request = rrm.id_repair_request
WHERE
    DATE(rr.ts_updated) BETWEEN '{load_start_date}' AND '{load_end_date}'
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rr.id_repair_request ORDER BY rr.ts_updated DESC) = 1
