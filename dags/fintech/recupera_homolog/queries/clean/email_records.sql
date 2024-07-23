SELECT
    id_creditor,
    id_customer,
    customer_email,
    type,
    CASE
        WHEN is_preferred_email = "P" THEN True
        ELSE False
    END AS is_preferred_email,
    CASE
        WHEN is_email_inactive = "S" THEN True
        ELSE False
    END AS is_email_inactive,
    customer_name,
    ts_load
FROM
    datalake_recupera_homolog_raw.email_records
