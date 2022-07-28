SELECT
    status,
    prestador AS provider,
    responsavel AS responsible,
    centro_de_custo AS cost_center,
    tipo_de_despesa AS expense_type,
    breve_descricao AS description,
    no_da_nf AS invoice_number,
    qtde_de_parcelas AS installments_quantity,
    frequencia AS frequency,
    n_solicitacao AS solicitation_number,
    doc AS documentation,
    competencia AS month_competence,
    CASE
        WHEN lancado_em_legal = 'Sim' THEN True
        ELSE False
    END AS is_launch_in_legal,
    CAST(REPLACE(REPLACE(REPLACE(valor_da_despesa, 'R$ ', ''), '.', ''), ',', '.') AS NUMERIC(10,2)) AS expense_value,
    CAST(REPLACE(REPLACE(REPLACE(valor_total_da_nfs, 'R$ ', ''), '.', ''), ',', '.') AS NUMERIC(10,2)) AS invoice_total_value,
    CAST(REPLACE(REPLACE(REPLACE(saldo_a_pagar, 'R$ ', ''), '.', ''), ',', '.') AS NUMERIC(10,2)) AS balance_to_pay_value,
    TO_DATE(data_lancto, 'dd/MM/yyyy') AS dt_launch,
    TO_DATE(data_estimada_vencto, 'dd/MM/yyyy') AS dt_estimated_due,
    TO_DATE(data_da_contratacao, 'dd/MM/yyyy') AS dt_hiring
FROM
    datalake_gsheets_raw.legal_provisioning