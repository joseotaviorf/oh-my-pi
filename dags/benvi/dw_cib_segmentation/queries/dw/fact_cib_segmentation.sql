SELECT
    id_cib || '.' || year || month || '01' AS pk_cib_segmentation,
    id_cib AS sk_cib,
    id_segmentation AS sk_segmentation,
    type_calculation,
    first_listings,
    contracts_signed,
    months_registered,
    months_calculation,
    dt_month_started_segmentation,
    dt_started,
    dt_ended,
    year,
    month
FROM
    datalake_mexico_cib_segmentation.cib_segmentation
WHERE
    dt_month_started_segmentation = MAKE_DATE({year},{month},{day}) + INTERVAL 1 DAY
