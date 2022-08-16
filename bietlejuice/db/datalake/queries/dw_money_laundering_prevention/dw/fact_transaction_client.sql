SELECT
    id_client AS sk_client,
    id_offer AS sk_offer,
    id_document AS sk_document,
    id_vendas AS sk_sales_flow,
    id_sale_flow_firestore AS sk_sale_flow_firestore,
    client_income_nature,
    client_monthly_income
FROM
    datalake_money_laundering_prevention.transaction_client