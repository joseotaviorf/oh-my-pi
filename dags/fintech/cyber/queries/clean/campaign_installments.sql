SELECT
    CPID AS id_campaign,
    CPNUMOFERTA AS id_offer,
    CPSSNUM AS id_client,
    CONCAT(CPNUMOFERTA ,LPAD(CPDETID, 3, '0')) AS id_agreement_installment,
    CPDETID AS installment_number,
    CPCPFCGC AS cpf_cnpj,
    CPAMT AS installment_amount,
    CPINTAMT AS installment_interest_amount,
    CPHONO AS installment_honorarium_amount,
    CPINTTAXAMT AS tax_amount,
    CPDUEDT AS ts_due_installment,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_campanha_ofer
