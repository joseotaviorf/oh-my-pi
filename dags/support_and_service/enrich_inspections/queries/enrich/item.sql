WITH item_type AS (
    SELECT
        id_item_type,
        it.type AS item_type,
        it.media_type,
        it.display_type
    FROM
        datalake_inspections_clean.item_type it
    QUALIFY
        it.ts_updated = FIRST(it.ts_updated) OVER(PARTITION BY it.id_item_type ORDER BY it.ts_updated DESC)
)
SELECT DISTINCT
    i.id_item,
    i.id_previous_item,
    it.id_item_type,
    i.id_item_group,
    i.id_main AS id_external_item,
    r.id_room,
    r.id_assessment,
    ih.id_inspection,
    ih.id_inspector,
    i.uuid,
    it.item_type,
    it.media_type,
    it.display_type,
    r.room_name,
    ig.item_group_name,
    ig.item_group_type,
    CASE
        WHEN i.comment = '' THEN NULL
        ELSE i.comment
    END AS comment,
    i.is_present,
    i.count,
    i.ts_created,
    i.ts_updated,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections_clean.item i
JOIN
    item_type it
        ON it.id_item_type = i.id_type
JOIN
    datalake_inspections.item_group ig
        ON ig.id_item_group = i.id_item_group
JOIN
    datalake_inspections_clean.room r
        ON r.id_room = ig.id_room
JOIN
    datalake_inspections.inspection_booking AS ih
        ON ih.id_assessment = r.id_assessment
WHERE
    i.year = {year}
    AND i.month = {month}
    AND i.day = {day}