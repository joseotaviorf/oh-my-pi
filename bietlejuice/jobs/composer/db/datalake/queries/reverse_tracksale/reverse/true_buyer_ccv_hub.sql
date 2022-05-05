WITH users AS (
    SELECT
    	 u.email,
    	 u.nome,
    	 u.telefone_principal,
    	 u.id,
    	 u.cpf
    FROM 
        dw_public.dim_user AS u 
),
ccvs AS (
    SELECT
    	TO_DATE(STRING(NULLIF(fo.sk_sale_agreement_signed_date, -1)), 'yyyyMMdd') AS dt_event,
    	fo.sk_house,
    	fo.sk_offer,
    	fo.sk_owner,
    	fo.sk_buyer,
    	fo.sk_sale_flow as sk_sales_flow,
    	DATEDIFF(current_date, TO_DATE(STRING(NULLIF(fo.sk_sale_agreement_signed_date, -1)), 'yyyyMMdd')) AS days_since_event
    FROM 
        dw_sale.fact_offers fo
    INNER JOIN 
        dw_sale.dim_offer df 
            ON df.sk_offer = fo.sk_offer
    WHERE
    	fo.sk_sale_agreement_signed_date >= 20200101
    	AND offer_flow = 'HUB'
)
SELECT 
    nome AS customer_name,
    email AS customer_email,
    telefone_principal AS customer_phone,
    'CCV' AS campaign_step,
    'Buyer' AS customer_type,
    cpf AS customer_cpf,
    u.id AS id_user,
    'true' AS campaign_type,
    'offer' AS driver_type,
    sk_offer AS id_driver,
    'Sale' as business_context,
    '' as cidade
FROM 
    ccvs AS c
INNER JOIN 
    users u 
        ON c.sk_buyer = u.id
WHERE
    days_since_event = 2