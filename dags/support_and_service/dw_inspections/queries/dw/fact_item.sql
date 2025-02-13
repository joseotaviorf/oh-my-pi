SELECT
    i.id_item AS sk_item,
    i.id_previous_item AS sk_previous_item,
    i.id_external_item AS sk_external_item,
    i.id_item_group AS sk_item_group,
    i.id_room AS sk_room,
    i.id_assessment AS sk_assessment,
    CAST(i.id_inspection AS STRING) AS sk_inspection,
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
    is_present = TRUE
    AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_item ORDER BY ts_updated DESC) = 1
