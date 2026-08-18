WITH ranked_item_review AS (
    SELECT
        ir.id_review AS sk_item_review,
        ir.id_item AS sk_item,
        ir.user_comment AS review_comment,
        ir.user_type AS review_creator,
        ir.ts_created,
        ir.ts_updated,
        ir.year,
        ir.month,
        ir.day,
        ROW_NUMBER() OVER (PARTITION BY ir.id_review ORDER BY ir.ts_updated DESC) AS rn
    FROM
        datalake_inspections.item_review AS ir
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT DISTINCT
    sk_item_review,
    sk_item,
    review_comment,
    review_creator,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    ranked_item_review
WHERE
    rn = 1
