SELECT DISTINCT
    ii.id_item_issue AS sk_item_issue,
    ii.id_item AS sk_item,
    ii.id_assessment AS sk_assessment,
    ii.id_inspection AS sk_inspection,
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
