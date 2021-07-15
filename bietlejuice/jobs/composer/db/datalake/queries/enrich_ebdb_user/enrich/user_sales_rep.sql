SELECT
    u.id AS id_user_sales_rep,
    u.name,
    u.email,
    u.main_phone AS phone_number,
    u.admin_type,
    CASE 
        WHEN u.id_sales_rep IS NOT NULL
            AND u.email LIKE '%@quintoandar.com.br' THEN 'QUINTO_ANDAR'
        WHEN u.email LIKE '%@actionline%.com.br' THEN 'ACTION_LINE'
        WHEN u.email LIKE '%@atento.com.br' THEN 'ATENTO'
        WHEN u.email LIKE '%@algar%' THEN 'ALGAR'
    END AS sales_company,
    COALESCE(sp.is_active, u.is_active) AS is_sales_rep_active,
    DATE(COALESCE(sp.ts_contract_started, u.ts_created)) AS dt_sales_rep_started
FROM datalake_ebdb_clean.user AS u 
LEFT JOIN
    datalake_ebdb_clean.sales_rep AS sp
        ON sp.id = u.id_sales_rep
WHERE 
    u.email LIKE '%@actionline.com.br' 
    OR u.email LIKE '%@atento.com.br' 
    OR u.email LIKE '%@algar%' 
    OR (u.id_sales_rep IS NOT NULL
        AND u.email LIKE '%@quintoandar.com.br')