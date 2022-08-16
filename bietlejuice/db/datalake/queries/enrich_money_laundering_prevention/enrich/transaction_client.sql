SELECT
    c.client_id AS id_client,
    t.id_offer,
    d.id_document,
    t.id_vendas,
    t.id_sale_flow_firestore,
    c.income_nature AS client_income_nature,
    c.monthly_income AS client_monthly_income
FROM
    datalake_money_laundering_prevention.client AS c
INNER JOIN datalake_money_laundering_prevention.transaction AS t
    ON t.id_buyer = c.client_id
INNER JOIN datalake_money_laundering_prevention.document AS d
    ON d.id_offer = t.id_offer
GROUP BY 
    1,2,3,4,5,6,7