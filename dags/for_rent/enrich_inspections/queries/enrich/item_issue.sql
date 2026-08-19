WITH issue_type_ranked AS (
    SELECT
        it.id_issue_type,
        it.type AS issue_type,
        it.repair_suggestion,
        -- RANK, not ROW_NUMBER: the original ts_updated = FIRST(ts_updated) OVER (...)
        -- kept every row tied on the latest ts_updated.
        RANK() OVER (PARTITION BY it.id_issue_type ORDER BY it.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.issue_type it
),
issue_type AS (
    SELECT
        id_issue_type,
        issue_type,
        repair_suggestion
    FROM
        issue_type_ranked
    WHERE
        rn = 1
),
item_issue_ranked AS (
    SELECT
        ii.id_item_issue,
        it.id_issue_type,
        ii.id_item,
        i.id_room,
        i.id_assessment,
        i.id_inspection,
        ii.uuid,
        it.issue_type,
        i.display_type,
        i.item_group_name,
        i.item_group_type,
        i.room_name,
        i.comment AS item_comment,
        CASE
            WHEN ii.comment = '' THEN NULL
            ELSE ii.comment
        END AS issue_comment,
        it.repair_suggestion,
        ii.is_active,
        ii.ts_created,
        ii.ts_updated,
        ii.year,
        ii.month,
        ii.day,
        ROW_NUMBER() OVER (PARTITION BY ii.id_item_issue ORDER BY ii.ts_updated DESC) AS rn
    FROM
        datalake_inspection_services_clean.item_issue AS ii
    JOIN
        issue_type AS it
            ON ii.id_type = it.id_issue_type
    LEFT JOIN
        datalake_inspections.item i
            ON i.id_item = ii.id_item
    WHERE
        MAKE_DATE(ii.year, ii.month, ii.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_item_issue,
    id_issue_type,
    id_item,
    id_room,
    id_assessment,
    id_inspection,
    uuid,
    issue_type,
    display_type,
    item_group_name,
    item_group_type,
    room_name,
    item_comment,
    issue_comment,
    repair_suggestion,
    is_active,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    item_issue_ranked
WHERE
    rn = 1
