SELECT
    CAST(Customer_Source_ID AS INT) AS id_customer_source,
    Code AS code,
    CAST(Creation_Date AS TIMESTAMP) AS dt_created_at,
    CAST(Expiration_Date AS TIMESTAMP) AS dt_expirate_at
FROM 
    datalake_gsheets_raw.voucherify_users