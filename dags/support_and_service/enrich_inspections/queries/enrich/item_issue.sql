WITH issue_type AS (
    SELECT
        it.id_issue_type,
        it.type AS issue_type,
        it.repair_suggestion
    FROM
        datalake_inspections_clean.issue_type it
    QUALIFY
        it.ts_updated = FIRST(it.ts_updated) OVER(PARTITION BY it.id_issue_type ORDER BY it.ts_updated DESC)
)
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
    ii.ts_created,
    ii.ts_updated,
    ii.year,
    ii.month,
    ii.day
FROM
    datalake_inspections_clean.item_issue AS ii
JOIN
    issue_type AS it
        ON ii.id_type = it.id_issue_type
LEFT JOIN
    datalake_inspections.item i
        ON i.id_item = ii.id_item
WHERE
    MAKE_DATE(ii.year, ii.month, ii.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ii.id_item_issue ORDER BY ii.ts_updated DESC) = 1
