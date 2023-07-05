SELECT DISTINCT
    COALESCE(fo.sk_buyer,-1) AS sk_buyer,
    du.cpf      AS buyer_cpf,
    du.nome     AS buyer_name,
    NOW()       AS ts_load
FROM
    dw_sale.fact_offers fo
LEFT JOIN
    dw_public.dim_user du
        ON fo.sk_buyer = du.sk_user
WHERE fo.sk_buyer IS NOT NULL
