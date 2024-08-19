SELECT
    HAID AS id_agreement,
    HAACCT AS id_contract,
    HASSNUM AS id_client,
    AHIDPARC AS id_invoice,
    HAACCTG AS contract_group,
    HADAYS AS contract_delay_days,
    HADLQDT AS ts_contract_expiration,
    HAMONTMI,
    HAMULTAFIXA,
    HAMULTADIARIA,
    HAVLENCPAGO,
    HAMIGRACAO,
    AHVLMULDV,
    AHVLPRINCDV,
    AHVLJURDV,
    HAIDPARC,
    HADTVENC
FROM datalake_cyber_raw.agr_hist
