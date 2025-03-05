SELECT
    CAST(sk_ticket AS BIGINT) AS id_ticket,
    CAST(sk_user AS BIGINT) AS id_user,
    CAST(sk_contract AS BIGINT) AS id_contract,
    status,
    is_pp_multi,
    data_abertura AS dt_opened
FROM
    datalake_gsheets_raw.nps_offboarding_contracts_dispatched
