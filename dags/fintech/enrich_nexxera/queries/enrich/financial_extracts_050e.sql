WITH datalake_nexxera_clean_financial_extracts_050e_0 AS  (
    SELECT DISTINCT
        dt_launch,
        launch_value,
        UPPER(LEFT(TRIM(REGEXP_EXTRACT(history_description, '^[^ ]+ ([^ ]+) .*$', 1)),4)) AS id_flag,
        CAST(REGEXP_EXTRACT(TRIM(history_description),'^[^0-9]+([0-9]+)$',1) AS INT) AS id_ec
    FROM
        datalake_nexxera_clean.financial_extracts_050e
    WHERE
        history_description LIKE 'GETNET%'
        AND launch_type = 'C'
        AND launch_category = '205'
    )
SELECT
    id_flag,
    id_ec,
    ROW_NUMBER() OVER(ORDER BY dt_launch, id_flag, id_ec) AS rn_bank,
    SUM(launch_value) AS launch_value,
    dt_launch
FROM
    datalake_nexxera_clean_financial_extracts_050e_0
WHERE
    CAST(ts_ingested AS DATE) < (CAST(NOW() AS DATE) - 1)
GROUP BY
    dt_launch,
    id_flag,
    id_ec
