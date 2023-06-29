SELECT
    CAST(contrato AS BIGINT) AS id_contract,
    pagante_condominio AS condo_payer,
    CAST(aluguel AS DOUBLE) AS rent,
    CAST(cota_condominial AS DOUBLE) AS condo,
    CAST(iptu AS DOUBLE) AS iptu,
    CAST(seguro_contra_incendio AS DOUBLE) AS fire_insurance_fee_value,
    CAST(taxa_de_servico AS DOUBLE) AS service_fee_value,
    responsavel_condominio AS condo_responsible,
    BOOLEAN(adiantado) AS is_paid_in_advance,
    TO_DATE(vigencia) AS dt_start,
    TO_DATE(rescisao) AS dt_termination,
    ts_load
FROM
    datalake_gsheets_raw.offboarding_payments_contracts
