SELECT
    id_segmentation AS sk_segmentation,
    segmentation AS segmentation_name,
    MAX(dt_month_started_segmentation) AS dt_last_segmentation,
    YEAR(MAX(dt_month_started_segmentation)) AS year,
    MONTH(MAX(dt_month_started_segmentation)) AS month
FROM
    datalake_mexico_cib_segmentation.cib_segmentation
GROUP BY
    1, 2
