SELECT
    im.id_item_media,
    im.id_item,
    im.id_main AS id_external_media,
    im.uuid,
    i.id_room,
    i.id_assessment,
    i.id_inspection,
    i.id_inspector AS id_user,
    "INSPECTOR" AS user_type,
    im.type AS media_type,
    im.url AS media_path,
    im.ts_created,
    im.ts_updated,
    im.year,
    im.month,
    im.day
FROM
    datalake_inspection_services_clean.item_media im
JOIN
    datalake_inspections.item i
        ON i.id_item = im.id_item
WHERE
    MAKE_DATE(im.year, im.month, im.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
