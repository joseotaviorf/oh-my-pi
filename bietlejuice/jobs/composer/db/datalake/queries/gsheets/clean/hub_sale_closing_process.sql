SELECT
    CAST(sk_house AS BIGINT) AS id_house,
    CAST(sk_owner AS BIGINT) AS id_owner,
    hub AS hub_offer,
    city AS city_group,
    state AS state_name,
    seller_name,
    seller_cpf_cnpj,
    CAST(sale_price_agreed AS FLOAT) AS sale_price_agreed,
    CAST(brokerage_fee_quintoandar AS FLOAT) AS brokerage_fee_quintoandar,
    CAST(brokerage_fee_partner AS FLOAT) AS brokerage_fee_partner,
    CAST(brokerage_fee AS FLOAT) AS brokerage_fee,
    TO_DATE(dt_process_start, 'dd/MM/yyyy') AS dt_process_started,
    TO_DATE(dt_sale, 'dd-MM-yyyy') AS dt_sale,
    TO_DATE(dt_ccv_signed, 'dd-MM-yyyy') AS dt_ccv_signed
FROM
    datalake_gsheets_raw.hub_sale_closing_process   