SELECT
    id AS id_proposal_product,
    id_cliente AS id_client,
    IDParceiro AS id_partner,
    IDFranquia AS id_franchise,
    id_itau,
    status_processo_obs AS financing_proposal_status_details,
    status_envio AS send_status,
    a_preco_estimado_imovel AS estimated_house_value,
    a_valor_a_financiar AS finance_value,
    a_valor_entrada AS down_payment_value,
    a_prazo_meses AS installments_quantity,
    a_fgts AS fgts_value,
    a_tipo_de_imovel AS house_category,
    a_incorporar_valor_despesas_ITBI_registro AS to_incorporate_costs_itbi_register_value,
    a_incorporar_tarifa_de_avaliacao AS to_incorporate_evaluation_fee_value,
    a_valor_tarifas AS fees_value,
    a_valor_despesas AS costs_value,
    TIMESTAMP(data_cadastro) AS ts_registration_financing_proposal,
    TIMESTAMP(data_envio) AS ts_send_financing_proposal
FROM
    datalake_atta_test_raw.proposta_itau
