WITH item_issue AS (
    SELECT
        ii.id_item,
        COUNT(DISTINCT ii.id_item_issue) AS total_item_issue
    FROM
        datalake_inspections.item_issue ii
    GROUP BY 1
),
comment_media AS (
    SELECT
        cm.id_item,
        COUNT(cm.id_media) AS total_media,
        SUM(
            CASE
                WHEN cm.user_type = 'INSPECTOR' AND cm.user_comment IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS total_inspector_comment,
        SUM(
            CASE
                WHEN cm.user_type = 'TENANT' AND cm.user_comment IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS total_tenant_comment,
        SUM(
            CASE
                WHEN cm.user_type = 'OWNER' AND cm.user_comment IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS total_owner_comment,
        MAX(
            CASE
                WHEN cm.user_type = 'INSPECTOR' AND cm.user_comment IS NOT NULL THEN TRUE
                ELSE FALSE
            END
        ) AS has_inspector_comment,
        MAX(
            CASE
                WHEN cm.user_type = 'TENANT' AND cm.user_comment IS NOT NULL THEN TRUE
                ELSE FALSE
            END
        ) AS has_tenant_comment,
        MAX(
            CASE
                WHEN cm.user_type = 'OWNER' AND cm.user_comment IS NOT NULL THEN TRUE
                ELSE FALSE
            END
        ) AS has_owner_comment
    FROM
        datalake_inspections.item_comment_media cm
    GROUP BY 1
)
SELECT DISTINCT
    i.id_item,
    i.id_previous_item,
    i.id_item_type,
    i.id_item_group,
    r.id_room,
    r.id_assessment,
    i.item_type,
    i.media_type AS inspection_media_type,
    ii.total_item_issue,
    cm.total_media,
    cm.total_inspector_comment,
    cm.total_tenant_comment,
    cm.total_owner_comment,
    CASE
        WHEN cm.total_media > 0 THEN TRUE
        ELSE FALSE
    END AS has_media,
    cm.has_inspector_comment,
    cm.has_tenant_comment,
    cm.has_owner_comment,
    CASE
        WHEN cm.has_tenant_comment IS TRUE
            OR cm.has_owner_comment IS TRUE
            OR cm.has_inspector_comment IS TRUE
        THEN TRUE
        ELSE FALSE
    END AS is_commented,
    i.ts_created,
    i.ts_updated,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections.item i
JOIN
    datalake_inspections.item_group ig
        ON ig.id_item_group = i.id_item_group
JOIN
    datalake_inspections.room r
        ON r.id_room = ig.id_room
JOIN
    comment_media cm
        ON cm.id_item = i.id_item
LEFT JOIN
    item_issue ii
        ON ii.id_item = i.id_item
WHERE
    i.year = {year}
    AND i.month = {month}
    AND i.day = {day}
