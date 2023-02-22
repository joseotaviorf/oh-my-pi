SELECT DISTINCT
    ii.id_item_issue AS sk_item_issue,
    ii.issue_type,
    ii.display_type,
    ii.issue_comment,
    ii.repair_suggestion,
    ii.ts_created,
    ii.ts_updated,
    NOW() AS ts_load,
    ii.year,
    ii.month,
    ii.day
FROM
    datalake_inspections.item_issue AS ii
WHERE
    ii.year = {year}
    AND ii.month = {month}
    AND ii.day = {day}
