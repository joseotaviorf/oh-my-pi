SELECT DISTINCT
    ii.id_item_issue AS sk_item_issue,
    ii.id_item AS sk_item,
    ii.id_assessment AS sk_assessment,
    CAST(ii.id_inspection AS STRING) AS sk_inspection,
    ii.ts_created,
    ii.ts_updated,
    NOW() AS ts_load,
    ii.year,
    ii.month,
    ii.day
FROM
    datalake_inspections.item_issue AS ii
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
