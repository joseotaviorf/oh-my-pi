WITH item_type AS (
    SELECT
        id_item_type,
        it.type AS item_type,
        it.media_type
    FROM
        datalake_inspections_clean.item_type it
    QUALIFY
        it.ts_updated = FIRST(it.ts_updated) OVER(PARTITION BY it.id_item_type ORDER BY it.ts_updated DESC)
)
SELECT
    i.id_item,
    i.id_previous_item,
    it.id_item_type,
    i.id_item_group,
    i.id_main,
    i.uuid,
    it.item_type,
    it.media_type,
    i.comment,
    i.present,
    i.count,
    i.status,
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
WHERE
    i.year = {year}
    AND i.month = {month}
    AND i.day = {day}