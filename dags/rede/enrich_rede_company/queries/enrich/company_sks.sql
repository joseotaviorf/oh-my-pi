WITH starting_value AS (
    SELECT
        COALESCE(MAX(sk_company), 0) AS max_sk_company
    FROM
        datalake_rede_company.company_sks
)
SELECT
    COALESCE(
        sk_company, -- Keep the sk_company if it is already defined, so it is durable
        sv.max_sk_company + MONOTONICALLY_INCREASING_ID() + 1 -- if not, use a number after the previous maximum value
    ) AS sk_company,
    c.id_company AS id_hubspot -- Natural key
FROM
    datalake_hubspot.company AS c,
    starting_value AS sv
LEFT JOIN 
    datalake_rede_company.company_sks AS cs
        ON c.id_company = cs.id_hubspot