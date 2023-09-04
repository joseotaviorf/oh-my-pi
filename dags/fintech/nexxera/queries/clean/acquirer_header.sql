SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS acquirer_code,
    "adjustments" AS source_file,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.adjustments -- headers from adjustments files
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND col_1 = 02

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS acquirer_code,
    "financial" AS source_file,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial -- headers from financial files
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND col_1 = 02

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS acquirer_code,
    "inadvance" AS source_file,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.inadvance -- headers from inadvance files
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND col_1 = 02

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS acquirer_code,
    "sales" AS source_file,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.sales -- headers from sales files
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND col_1 = 02

UNION ALL

SELECT
    col_1 AS id_registration,
    col_2 AS group_name,
    col_3 AS group_cnpj,
    col_4 AS acquirer_name,
    col_5 AS acquirer_code,
    "transaction" AS source_file,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.transaction -- headers from transaction files
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND col_1 = 02
