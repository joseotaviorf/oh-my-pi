SELECT
    CAST(id AS INT) AS id_suspicion,
    nome_novo AS name,
    nome_antigo AS old_name,
    risco_de_pld AS money_laundering_risk,
    tipo_de_situacao AS suspicion_type,
    ref_jira,
    ref_siscoaf,
    newops,
    legaut,
    triagem AS sorting,
    confeccao AS confection,
    risk_diligencia AS diligence_risk,
    crn,
    cri,
    financiado AS funded,
    a_vista AS prompt_payment,
    bancos AS banks
FROM 
    datalake_gsheets_raw.pld_suspicion_list