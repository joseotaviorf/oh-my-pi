SELECT
    pkportal AS id_portal,
    fkrede AS id_network,
    fkportal_poolflex AS id_pool_flex,
    nome AS name,
    site AS website,
    email,
    responsavel AS account_owner,
    paratime AS dt_paratime
FROM
    datalake_union_cdc_raw.portal
