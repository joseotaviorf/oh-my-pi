WITH total_contestations AS (
    SELECT
        id_repair_request,
        COUNT(CASE WHEN reviewer_type = 'TENANT' AND (origin = 'REVIEW' OR origin IS NULL) THEN 1 END) AS total_tenant_contestation,
        COUNT(CASE WHEN reviewer_type = 'TENANT' AND origin = 'BUDGET_APPROVAL' THEN 1 END) AS total_tenant_budget_approval_contestation,
        COUNT(CASE WHEN reviewer_type = 'OWNER' AND origin = 'BUDGET_APPROVAL' THEN 1 END) AS total_owner_budget_approval_contestation
    FROM
        datalake_inspection_services_clean.contestation AS c
    LEFT JOIN
        datalake_inspection_services_clean.reviewer AS r
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
),
ar_ranked AS (
    SELECT
        id_repair_request,
        cost AS ar_cost,
        cost_source AS ar_cost_source,
        ts_updated AS ts_ar_cost,
        ROW_NUMBER() OVER (
            PARTITION BY id_repair_request
            ORDER BY ts_updated DESC                            
        ) AS rn
    FROM
        datalake_inspection_services_clean.repair_request_history
    WHERE
        origin = 'REPAIR_ANALYSIS'
        AND cost IS NOT NULL
),
ar_stage AS (
    SELECT
        id_repair_request,
        ar_cost,
        ar_cost_source,
        ts_ar_cost
    FROM    
        ar_ranked
    WHERE
        rn = 1
),
repair_request_ranked AS (
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
    ig.name AS item_name,
    ro.room_name,
    rr.cost,
    ars.ar_cost,
    ars.ar_cost_source,
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
    rev2.reviewer_type = 'OWNER' AND rr.is_exempted IS TRUE AS is_exempted_by_owner,
    CASE
      WHEN rr.is_finished = false AND rev2.reviewer_type = 'ADMIN' AND rr.is_exempted = true THEN true
      ELSE false
    END AS exempted_on_ar,
    rr.ts_created,
    rr.ts_updated,
    rr.ts_granted,
    rr.year,
    rr.month,
    rr.day,
    ROW_NUMBER() OVER (PARTITION BY rr.id_repair_request ORDER BY rr.ts_updated DESC, c.id_contestation DESC) AS rn
FROM
    datalake_inspection_services_clean.repair_request AS rr
LEFT JOIN
    datalake_inspection_services_clean.item_group AS ig
      ON rr.id_item_group = ig.id_item_group
LEFT JOIN
    datalake_inspection_services_clean.room AS ro
      ON ro.id_room = ig.id_room
LEFT JOIN
    datalake_inspection_services_clean.assessment AS asm
      ON asm.id_assessment = ro.id_assessment
LEFT JOIN
    datalake_inspection_services_clean.inspection AS ins
      ON ins.id_inspection = asm.id_inspection
LEFT JOIN
    datalake_inspection_services_clean.reviewer AS rev1
      ON rev1.id_reviewer = rr.id_reviewer
LEFT JOIN
    datalake_inspection_services_clean.reviewer AS rev2
      ON rev2.id_reviewer = rr.id_granted_by
LEFT JOIN
    total_contestations AS tc
      ON tc.id_repair_request = rr.id_repair_request
LEFT JOIN
    datalake_inspection_services_clean.contestation AS c
      ON rr.id_repair_request = c.id_repair_request
LEFT JOIN
    repair_request_media AS rrm
      ON rr.id_repair_request = rrm.id_repair_request
LEFT JOIN
    ar_stage AS ars
      ON ars.id_repair_request = rr.id_repair_request
)
SELECT
    id_repair_request,
    id_inspection,
    id_contract,
    id_contestation,
    id_item_group,
    id_room,
    id_assessment,
    id_requester,
    id_granted_by,
    id_contestation_requester,
    requester_type,
    granted_type,
    responsibility,
    repair_type,
    type,
    item_name,
    room_name,
    cost,
    ar_cost,
    ar_cost_source,
    repair_service,
    comment,
    total_media,
    total_tenant_contestation,
    total_tenant_budget_approval_contestation,
    total_owner_budget_approval_contestation,
    has_automatically_identified,
    has_automatic_identification_accepted,
    is_cost_absorbed_by_company,
    is_cost_absorbed_by_tenant,
    is_cost_absorbed_by_owner,
    is_finished,
    is_exempted,
    is_exempted_by_owner_from_budget,
    is_requested_by_owner,
    is_exempted_by_owner,
    exempted_on_ar,
    ts_created,
    ts_updated,
    ts_granted,
    year,
    month,
    day
FROM
    repair_request_ranked
WHERE
    rn = 1
