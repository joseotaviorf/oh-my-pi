WITH src_ranked AS (
    SELECT
        src.serial,
        src.description,
        src.stock_type,
        src.is_galipro,
        src.dt_validity_started,
        src.dt_validity_ended,
        ROW_NUMBER() OVER (
            PARTITION BY
                src.serial
            ORDER BY
                src.ts_load DESC NULLS LAST,
                src.year DESC,
                src.month DESC,
                src.day DESC
        ) AS rn_dedup
    FROM
        datalake_plugify_clean.available_device AS src
    WHERE
        src.serial IS NOT NULL
)
SELECT
    MD5(serial) AS sk_available_device,
    serial AS id_serial,
    description,
    stock_type,
    is_galipro,
    dt_validity_started,
    dt_validity_ended,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    src_ranked
WHERE
    rn_dedup = 1
