SELECT
    ig.id_item_group AS sk_item_group,
    ig.item_group_name,
    ig.item_group_type,
    ig.status,
    ig.is_inferior_quality,
    ig.ts_created,
    ig.ts_updated,
    ig.year,
    ig.month,
    ig.day
FROM
    datalake_inspections.item_group AS ig
WHERE
    ig.year = {year}
    AND ig.month = {month}
    AND ig.day = {day}
