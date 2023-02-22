SELECT
    i.id_item AS sk_item,
    i.id_previous_item AS sk_previous_item,
    i.id_external_item AS sk_external_item,
    i.id_item_group AS sk_item_group,
    i.id_room AS sk_room,
    i.id_assessment AS sk_assessment,
    i.id_inspection AS sk_inspection,
    i.comment IS NOT NULL AS has_inspector_comment,
    i.is_present,
    i.ts_created,
    i.ts_updated,
    NOW() AS ts_load,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections.item i
WHERE
    i.year = {year}
    AND i.month = {month}
    AND i.day = {day}