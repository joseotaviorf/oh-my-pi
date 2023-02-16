SELECT DISTINCT
    ir.id_review AS sk_review,
    ir.user_comment AS review_comment,
    ir.ts_created,
    ir.ts_updated,
    ir.year,
    ir.month,
    ir.day
FROM
    datalake_inspections.item_review AS ir
WHERE
    ir.year = {year}
    AND ir.month = {month}
    AND ir.day = {day}