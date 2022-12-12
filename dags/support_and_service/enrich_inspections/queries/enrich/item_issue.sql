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
    ii.uuid,
    it.issue_type,
    ii.comment,
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
WHERE
    ii.year = {year}
    AND ii.month = {month}
    AND ii.day = {day}
