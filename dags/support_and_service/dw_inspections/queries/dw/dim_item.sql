SELECT DISTINCT
    i.id_item AS sk_item,
    i.item_type,
    i.inspection_media_type,
    i.is_commented,
    i.ts_created,
    i.ts_updated,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections_metrics.item_description i
WHERE
    i.year = {year}
    AND i.month = {month}
    AND i.day = {day}
