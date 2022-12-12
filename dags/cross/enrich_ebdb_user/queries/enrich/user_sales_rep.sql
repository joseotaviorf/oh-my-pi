SELECT
    u.id AS id_user_sales_rep,
    ur.country_code,
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
        WHEN u.email LIKE '%@aec%' THEN 'AEC'
        WHEN u.email LIKE '%@olos%' THEN 'OLOS'
    END AS sales_company,
    COALESCE(sp.is_active, u.is_active) AS is_sales_rep_active,
    DATE(COALESCE(sp.ts_contract_started, u.ts_created)) AS dt_sales_rep_started
FROM
    datalake_ebdb_clean.user AS u
JOIN
    datalake_ebdb_country.user AS ur
        ON u.id = ur.id_user
LEFT JOIN
    datalake_ebdb_clean.sales_rep AS sp
        ON sp.id = u.id_sales_rep
WHERE 
    u.email LIKE '%@actionline.com.br' 
    OR u.email LIKE '%@atento.com.br' 
    OR u.email LIKE '%@algar%' 
    OR u.email LIKE '%@aec%' 
    OR u.email LIKE '%@olos%' 
    OR (u.id_sales_rep IS NOT NULL
        AND u.email LIKE '%@quintoandar.com.br')