WITH distinct_users AS (
    SELECT DISTINCT
        id_external,
        id_user
    FROM
        datalake_sale_offer_flows.sale_offer_users
)
SELECT
    dist_u.id_user AS sk_user_sales_flow,
    dist_u.id_external AS sk_user_external,
    du.nome AS name,
    CASE
        WHEN du.sexo IS NULL THEN "Unknown"
        ELSE du.sexo
    END AS gender,
    du.email,
    CASE
        WHEN du.email_alternativo IS NULL THEN "Unknown"
        ELSE du.email_alternativo
    END AS alternative_email,
    du.telefone_principal AS phone_number,
    CASE
        WHEN du.endereco IS NULL THEN "Unknown"
        ELSE du.endereco
    END AS address,
    CASE
        WHEN du.cep IS NULL THEN "Unknown"
        ELSE du.cep
    END AS postal_code,
    CASE
        WHEN du.cidade IS NULL THEN "Unknown"
        ELSE du.cidade
    END AS city,
    CASE
        WHEN du.estado_nome IS NULL THEN "Unknown"
        ELSE du.estado_nome
    END AS state,
    du.houses_owned,
    du.quintoandar_houses_owned,
    CASE
        WHEN du.tem_imovel = 1 THEN "Has a property"
        ELSE "Does not have a property"
    END AS owns_a_property,
    CASE
        WHEN du.tem_contrato_ativo = 1 THEN "Has an active contract"
        ELSE "Does not have an active contract"
    END AS active_contract_status,
    CASE
        WHEN du.active = 1 THEN "Active"
        ELSE "Not Active"
    END AS user_status,
    CASE
        WHEN du.bloqueado = 1 THEN "Blocked"
        ELSE "Not Blocked"
    END AS block_status
FROM
    distinct_users AS dist_u
LEFT JOIN
    dw_public.dim_user AS du
        ON du.id = dist_u.id_external
