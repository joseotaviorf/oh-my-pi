SELECT DISTINCT
    ir.id_review AS sk_item_review,
    ir.id_item AS sk_item,
    ir.user_comment AS review_comment,
    ir.user_type AS review_creator,
    ir.ts_created,
    ir.ts_updated,
    NOW() AS ts_load,
    ir.year,
    ir.month,
    ir.day
FROM
    datalake_inspections.item_review AS ir
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')