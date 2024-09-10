WITH inspection_reviewer AS (
    SELECT DISTINCT
        r.id_reviewer,
        r.id_user,
        r.reviewer_type,
        r.id_assessment,
        r.id_inspection
    FROM
        datalake_inspections.reviewer AS r
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
contestation AS (
    SELECT
        c.id_repair_request,
        COUNT(DISTINCT id_contestation) FILTER(WHERE ir.reviewer_type = "TENANT") AS total_tenant_contestation,
        COUNT(DISTINCT id_contestation) FILTER(WHERE ir.reviewer_type = "OWNER") AS total_owner_contestation
    FROM
        datalake_inspections_clean.contestation AS c
    JOIN
        inspection_reviewer AS ir
        ON ir.id_reviewer = c.id_reviewer
    GROUP BY 1
)
SELECT DISTINCT
    rr.id_repair_request AS sk_repair_request,
    rr.id_item_group AS sk_item_group,
    ig.id_room AS sk_room,
    ir.id_assessment AS sk_assessment,
    ir.id_inspection AS sk_inspection,
    rr.id_reviewer AS sk_requester,
    rr.id_granted_by AS sk_granted_by,
    COALESCE(rrm.total_media, 0) <> 0 AS has_media,
    COALESCE(c.total_tenant_contestation, 0) <> 0 AS has_tenant_contestation,
    COALESCE(c.total_owner_contestation, 0) <> 0 AS has_owner_contestation,
    CASE
        WHEN rr.responsibility = "ABSORBED_BY_COMPANY" THEN TRUE
        WHEN rr.is_exempted IS TRUE 
            OR rr.responsibility <> "ABSORBED_BY_COMPANY"
            THEN FALSE
    END AS is_cost_absorbed_by_company,
    CASE
        WHEN rr.responsibility = "TENANT" THEN TRUE
        WHEN rr.is_exempted IS TRUE 
            OR rr.responsibility <> "TENANT"
            THEN FALSE
    END AS is_cost_absorbed_by_tenant,
    CASE
        WHEN rr.is_exempted IS TRUE 
            OR rr.responsibility = "OWNER"
            THEN TRUE
        WHEN rr.is_exempted IS FALSE 
            OR rr.responsibility <> "OWNER"
            THEN FALSE
    END AS is_cost_absorbed_by_owner,
    rr.is_exempted,
    ir2.reviewer_type = "OWNER" AS is_exempted_by_owner,
    ir.reviewer_type = "OWNER" AS is_requested_by_owner,
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
    datalake_inspections_clean.repair_request AS rr
JOIN
    datalake_inspections.item_group AS ig
        ON ig.id_item_group = rr.id_item_group
LEFT JOIN
    inspection_reviewer AS ir
        ON ir.id_reviewer = rr.id_reviewer
LEFT JOIN
    inspection_reviewer AS ir2
        ON ir2.id_reviewer = rr.id_granted_by
LEFT JOIN
    repair_request_media AS rrm
        ON rrm.id_repair_request = rr.id_repair_request
LEFT JOIN
    contestation AS c
        ON c.id_repair_request = rr.id_repair_request
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rr.id_repair_request ORDER BY rr.ts_updated DESC) = 1
