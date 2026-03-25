SELECT
    i.id AS id_entity,
    cc.id_house,
    cc.id_contract,
    CASE
        WHEN ai.type = 'tenant' THEN COALESCE(ai.id_main_user, cc.id_tenant)
        WHEN ai.type = 'landlord' THEN COALESCE(ai.id_main_user, cc.id_owner)
    END AS id_user,
    'FR_INVOICE' AS entity,
    CASE
        WHEN ai.type = 'tenant' THEN 'TENANT'
        WHEN ai.type = 'landlord' THEN 'OWNER'
    END AS persona,
    'RENT' AS business_context,
    TO_JSON(
        STRUCT(
            i.status AS status,
            i.ts_created AS when
        )
    ) AS properties,
    CASE
        WHEN i.status = 'open' THEN TRUE
        WHEN i.status IN ('divergent-payment', 'not-payable', 'written-down', 'canceled', 'paid') THEN FALSE
        ELSE NULL
    END AS is_active,
    i.ts_created,
    i.ts_retsuko_updated AS ts_updated
FROM
    datalake_retsuko_clean.invoice AS i
LEFT JOIN
    datalake_retsuko_clean.account AS ai
        ON i.id_account = ai.id
LEFT JOIN
    datalake_retsuko_clean.contract AS c
        ON c.id = i.id_contract
JOIN
    core_contract.contract AS cc
        ON c.id_external = cc.id_contract
