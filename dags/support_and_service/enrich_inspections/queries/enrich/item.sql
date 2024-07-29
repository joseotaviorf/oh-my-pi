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
LEFT JOIN
    item_type it
        ON i.id_type = it.id_item_type
LEFT JOIN
    datalake_inspections.item_group ig
        ON i.id_item_group = ig.id_item_group
LEFT JOIN
    datalake_inspections_clean.room r
        ON ig.id_room = r.id_room
LEFT JOIN
    datalake_inspections_clean.assessment AS a
        ON r.id_assessment = a.id_assessment
LEFT JOIN
    datalake_inspections_clean.inspection AS ih
        ON a.id_inspection = ih.id_inspection
WHERE
    MAKE_DATE(i.year, i.month, i.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
