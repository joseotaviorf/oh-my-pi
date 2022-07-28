WITH consultant_prep AS (
    SELECT
        id_offer,
        CASE
            WHEN SPLIT_PART(REPLACE(id_consultant, ']', ''),',', 2) = '11422665'
            THEN SPLIT_PART(REPLACE(id_consultant, '[', ''),',', 1)
            WHEN id_consultant NOT LIKE '%,%'
            THEN REPLACE(REPLACE(id_consultant, ']', ''), '[', '')
            ELSE SPLIT_PART(REPLACE(id_consultant, ']', ''),',', 2)
        END AS id_consultant,
        id_closing_specialist
    FROM
        datalake_firestore_prod.monday AS dfm
),
consultant_prep_rules AS (
    SELECT
        cp.id_offer,
        CASE
            WHEN id_consultant = '11422665' THEN '12614540'
            ELSE id_consultant
        END AS id_consultant_adjusted,
        ms.id_monday AS id_closing_specialist,
        CASE
            WHEN id_consultant IS NULL THEN 'não atribuido'
            ELSE mu.user_name
        END AS name_consultant,
        ms.user_email AS closing_specialist_email
    FROM
        consultant_prep cp
    LEFT JOIN
        datalake_gsheets_clean_prod.monday_users AS mu
        ON mu.id_monday = cp.id_consultant
    LEFT JOIN
        datalake_gsheets_clean_prod.monday_users AS ms
        ON ms.id_monday = cp.id_closing_specialist
),
offer_rules AS (
    SELECT
        so.id AS id_offer,
        dfm.sale_agreement_status,
        CASE
            WHEN dfm.status = 'Propostas em validação' THEN 'Ongoing'
            WHEN dfm.status = 'Propostas Ongoing' THEN 'Ongoing'
            WHEN dfm.status = 'Propostas Aceitas' THEN 'Accepted Ongoing'
            WHEN dfm.status = 'Pós CCV' THEN 'CCV Assinado'
            WHEN dfm.status = 'Compra e Venda Concluídas' THEN 'CCV Assinado'
            WHEN dfm.status = 'CCV - Cancelado' THEN 'CCV Assinado'
            WHEN dfm.status = 'Canceladas pós Aceite' THEN 'Descarte'
            WHEN dfm.status = 'Canceladas em negociação' THEN 'Descarte'
            WHEN dfm.status = 'Canceladas em validação' THEN 'Descarte'
            ELSE 'ERRO'
        END AS status_type,
        CASE
            WHEN dt_offer_dismissed IS NOT NULL OR dfm.drop_reason IS NOT NULL THEN TRUE ELSE FALSE
        END AS is_offer_dismissed,
        CASE
            WHEN dfm.drop_reason IS NULL AND dfm.dt_offer_dismissed is NULL THEN ''
            WHEN len(dfm.drop_reason) > 4 THEN dfm.drop_reason
            WHEN dfm.drop_reason = 120 THEN 'BY - Vai procurar outro imóvel dentro do 5A'
            WHEN dfm.drop_reason = 121 THEN 'BY - Vai procurar outro imóvel fora do 5A'
            WHEN dfm.drop_reason = 122 THEN 'BY - Pagamento parcelado'
            WHEN dfm.drop_reason = 123 THEN 'BY - Pagamento permuta'
            WHEN dfm.drop_reason = 124 THEN 'BY - Pagamento aluguel investido'
            WHEN dfm.drop_reason = 125 THEN 'BY - Sem contato/retorno'
            WHEN dfm.drop_reason = 126 THEN 'BY - Não possui valor de entrada/sinal (qualquer imóvel)'
            WHEN dfm.drop_reason = 127 THEN 'BY - Não possui valor de entrada/sinal (deste imóvel)'
            WHEN dfm.drop_reason = 128 THEN 'BY - Não aceitou a contra SL'
            WHEN dfm.drop_reason = 129 THEN 'BY - Não aceita modelo 5A'
            WHEN dfm.drop_reason = 130 THEN 'BY - Alugou ou comprou fora do 5A'
            WHEN dfm.drop_reason = 131 THEN 'BY - Financiamento do BY não cobre o do SL'
            WHEN dfm.drop_reason = 132 THEN 'BY - Desistiu de comprar qualquer imóvel'
            WHEN dfm.drop_reason = 133 THEN 'BY - Comprou outro imóvel pelo 5A'
            WHEN dfm.drop_reason = 134 THEN 'BY - Não tem o valor para as custas de cartório'
            WHEN dfm.drop_reason = 135 THEN 'BY - Falta de flexibilização em cláusulas contratuais'
            WHEN dfm.drop_reason = 136 THEN 'SL - Vendeu por fora do 5A'
            WHEN dfm.drop_reason = 137 THEN 'SL - Vendeu pelo 5A para outro buyer'
            WHEN dfm.drop_reason = 138 THEN 'SL - IQ dificultou processo de venda'
            WHEN dfm.drop_reason = 139 THEN 'SL- Problemas de documentação do imóvel'
            WHEN dfm.drop_reason = 140 THEN 'SL - Problemas de documentação do vendedor'
            WHEN dfm.drop_reason = 141 THEN 'SL - Sem contato/retorno'
            WHEN dfm.drop_reason = 142 THEN 'SL - Desistiu de vender o imóvel'
            WHEN dfm.drop_reason = 143 THEN 'SL - Só aceita valor do anuncio'
            WHEN dfm.drop_reason = 144 THEN 'SL - Não aceitou contraproposta do BY'
            WHEN dfm.drop_reason = 145 THEN 'SL - Só aceita pagamento à vista'
            WHEN dfm.drop_reason = 146 THEN 'SL - Anúncio com valor incorreto'
            WHEN dfm.drop_reason = 147 THEN 'SL - Alugou ou vai alugar o imóvel'
            WHEN dfm.drop_reason = 148 THEN 'SL - Possível Bypass'
            WHEN dfm.drop_reason = 149 THEN 'SL - Não aceita modelo 5A'
            WHEN dfm.drop_reason = 150 THEN 'SL - Não concorda com taxa de corretagem'
            WHEN dfm.drop_reason = 151 THEN 'SL - Falta de flexibilização em cláusulas contratuais'
            WHEN dfm.drop_reason = 1 THEN 'Buyer - pagamento envolve permuta'
            WHEN dfm.drop_reason = 2 THEN 'Buyer - pagamento envolve aluguel investido'
            WHEN dfm.drop_reason = 3 THEN 'Buyer - pagamento parcelado'
            WHEN dfm.drop_reason = 4 THEN 'Buyer - não tem dinheiro para a entrada de qualquer imóvel'
            WHEN dfm.drop_reason = 5 THEN 'Buyer - não aceita modelo 5A'
            WHEN dfm.drop_reason = 7 THEN 'Buyer - não aceitou a contraproposta do Seller'
            WHEN dfm.drop_reason = 8 THEN 'Buyer - vai procurar outro imóvel'
            WHEN dfm.drop_reason = 9 THEN 'Buyer - pediu para desconsiderar a proposta'
            WHEN dfm.drop_reason = 10 THEN 'Buyer - nunca atende'
            WHEN dfm.drop_reason = 11 THEN 'Buyer - demora para retornar'
            WHEN dfm.drop_reason = 12 THEN 'Seller - não aceitou proposta do buyer (sem contraproposta)'
            WHEN dfm.drop_reason = 13 THEN 'Buyer - desistiu de comprar qualquer imóvel'
            WHEN dfm.drop_reason = 14 THEN 'Seller - não aceitou contraproposta do buyer'
            WHEN dfm.drop_reason = 15 THEN 'Buyer - já alugou ou comprou com outra imobiliária'
            WHEN dfm.drop_reason = 16 THEN 'Seller - problemas de documentação do Imóvel'
            WHEN dfm.drop_reason = 17 THEN 'Seller - condições legais (que não a documentação do Imóvel)'
            WHEN dfm.drop_reason = 18 THEN 'Seller - vendeu por outra imobiliária'
            WHEN dfm.drop_reason = 19 THEN 'Seller - alugou ou vai alugar o imóvel'
            WHEN dfm.drop_reason = 20 THEN 'Seller - não vai mais vender o imóvel'
            WHEN dfm.drop_reason = 102 THEN 'Seller - nunca atende'
            WHEN dfm.drop_reason = 103 THEN 'Seller - demora para retornar'
            WHEN dfm.drop_reason = 104 THEN 'Seller - não aceita modelo 5A'
            WHEN dfm.drop_reason = 105 THEN 'Seller - problemas para visitar o imóvel'
            WHEN dfm.drop_reason = 106 THEN 'Seller - IQ dificultou processo de venda'
            WHEN dfm.drop_reason = 107 THEN 'Buyer - não tem dinheiro para a entrada (deste imóvel)'
            WHEN dfm.drop_reason = 108 THEN 'Seller - anúncio com valor incorreto'
            WHEN dfm.drop_reason = 109 THEN 'Seller - seller é PJ'
            WHEN dfm.drop_reason = 110 THEN 'Buyer - comprou outro imóvel pelo 5A'
            WHEN dfm.drop_reason = 111 THEN 'Seller - vendeu pelo 5A para outro buyer'
            WHEN dfm.drop_reason = 112 THEN 'Buyer - problemas de documentação'
            WHEN dfm.drop_reason = 113 THEN 'Buyer - financiamento do Buyer não cobre o do Seller'
            WHEN dfm.drop_reason = 114 THEN 'Seller - não aceita pagamento financiado'
            WHEN dfm.drop_reason = 115 THEN 'Buyer - desconto maior do que 30%'
            WHEN dfm.drop_reason = 116 THEN 'Buyer - pediu para desconsiderar a proposta'
            WHEN dfm.drop_reason = 117 THEN 'Buyer - Proposta aceita invalidada'
            WHEN dfm.drop_reason = 118 THEN 'Seller - Proposta aceita invalidada'
            WHEN dfm.drop_reason = 119 THEN 'Possível Bypass'
            ELSE 'ERRO'
        END AS drop_reason_name,
        CASE
            WHEN dfm.drop_reason IS NULL AND dfm.dt_offer_dismissed IS NULL THEN ''
            WHEN dfm.drop_reason = 120 THEN 'Quali'
            WHEN dfm.drop_reason = 121 THEN 'Quali'
            WHEN dfm.drop_reason = 122 THEN 'Não Quali'
            WHEN dfm.drop_reason = 123 THEN 'Não Quali'
            WHEN dfm.drop_reason = 124 THEN 'Não Quali'
            WHEN dfm.drop_reason = 125 THEN 'Não Quali'
            WHEN dfm.drop_reason = 126 THEN 'Não Quali'
            WHEN dfm.drop_reason = 127 THEN 'Quali'
            WHEN dfm.drop_reason = 128 THEN 'Quali'
            WHEN dfm.drop_reason = 129 THEN 'Não Quali'
            WHEN dfm.drop_reason = 130 THEN 'Quali'
            WHEN dfm.drop_reason = 131 THEN 'Não Quali'
            WHEN dfm.drop_reason = 132 THEN 'Não Quali'
            WHEN dfm.drop_reason = 133 THEN 'Quali'
            WHEN dfm.drop_reason = 134 THEN 'Não Quali'
            WHEN dfm.drop_reason = 135 THEN 'Quali'
            WHEN dfm.drop_reason = 136 THEN 'Quali'
            WHEN dfm.drop_reason = 137 THEN 'Quali'
            WHEN dfm.drop_reason = 138 THEN 'Não Quali'
            WHEN dfm.drop_reason = 139 THEN 'Não Quali'
            WHEN dfm.drop_reason = 140 THEN 'Não Quali'
            WHEN dfm.drop_reason = 141 THEN 'Não Quali'
            WHEN dfm.drop_reason = 142 THEN 'Não Quali'
            WHEN dfm.drop_reason = 143 THEN 'Quali'
            WHEN dfm.drop_reason = 144 THEN 'Quali'
            WHEN dfm.drop_reason = 145 THEN 'Quali'
            WHEN dfm.drop_reason = 146 THEN 'Não Quali'
            WHEN dfm.drop_reason = 147 THEN 'Não Quali'
            WHEN dfm.drop_reason = 148 THEN 'Quali'
            WHEN dfm.drop_reason = 149 THEN 'Não Quali'
            WHEN dfm.drop_reason = 150 THEN 'Quali'
            WHEN dfm.drop_reason = 151 THEN 'Quali'
            WHEN dfm.drop_reason = 1 THEN 'Não Quali'
            WHEN dfm.drop_reason = 2 THEN 'Não Quali'
            WHEN dfm.drop_reason = 3 THEN 'Não Quali'
            WHEN dfm.drop_reason = 4 THEN 'Não Quali'
            WHEN dfm.drop_reason = 5 THEN 'Quali'
            WHEN dfm.drop_reason = 7 THEN 'Quali'
            WHEN dfm.drop_reason = 8 THEN 'Quali'
            WHEN dfm.drop_reason = 9 THEN 'Não Quali'
            WHEN dfm.drop_reason = 10 THEN 'Não Quali'
            WHEN dfm.drop_reason = 11 THEN 'Quali'
            WHEN dfm.drop_reason = 12 THEN 'Quali'
            WHEN dfm.drop_reason = 13 THEN 'Quali'
            WHEN dfm.drop_reason = 14 THEN 'Quali'
            WHEN dfm.drop_reason = 15 THEN 'Quali'
            WHEN dfm.drop_reason = 16 THEN 'Não Quali'
            WHEN dfm.drop_reason = 17 THEN 'Quali'
            WHEN dfm.drop_reason = 18 THEN 'Quali'
            WHEN dfm.drop_reason = 19 THEN 'Quali'
            WHEN dfm.drop_reason = 20 THEN 'Quali'
            WHEN dfm.drop_reason = 102 THEN 'Não Quali'
            WHEN dfm.drop_reason = 103 THEN 'Quali'
            WHEN dfm.drop_reason = 104 THEN 'Quali'
            WHEN dfm.drop_reason = 105 THEN 'Quali'
            WHEN dfm.drop_reason = 106 THEN 'Quali'
            WHEN dfm.drop_reason = 107 THEN 'Não Quali'
            WHEN dfm.drop_reason = 108 THEN 'Não Quali'
            WHEN dfm.drop_reason = 109 THEN 'Não Quali'
            WHEN dfm.drop_reason = 110 THEN 'Quali'
            WHEN dfm.drop_reason = 111 THEN 'Não Quali'
            WHEN dfm.drop_reason = 112 THEN 'Não Quali'
            WHEN dfm.drop_reason = 113 THEN 'Quali'
            WHEN dfm.drop_reason = 114 THEN 'Quali'
            WHEN dfm.drop_reason = 115 THEN 'Não Quali'
            WHEN dfm.drop_reason = 116 THEN 'Não Quali'
            WHEN dfm.drop_reason = 117 THEN 'Não Quali'
            WHEN dfm.drop_reason = 118 THEN 'Não Quali'
            WHEN dfm.drop_reason = 119 THEN 'Quali'
            ELSE 'ERRO'
        END AS drop_category,
        CASE
            WHEN dfm.drop_reason IS NULL AND dfm.dt_offer_dismissed IS NULL THEN ''
            WHEN dfm.drop_reason = 120 THEN 'Cliente 5A'
            WHEN dfm.drop_reason = 121 THEN 'Concorrência'
            WHEN dfm.drop_reason = 122 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 123 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 124 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 125 THEN 'Desistência'
            WHEN dfm.drop_reason = 126 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 127 THEN 'Problema Jurídico/Financeiro'
            WHEN dfm.drop_reason = 128 THEN 'Negociação'
            WHEN dfm.drop_reason = 129 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 130 THEN 'Concorrência'
            WHEN dfm.drop_reason = 131 THEN 'Problema Jurídico/Financeiro'
            WHEN dfm.drop_reason = 132 THEN 'Desistência'
            WHEN dfm.drop_reason = 133 THEN 'Cliente 5A'
            WHEN dfm.drop_reason = 134 THEN 'Problema Jurídico/Financeiro'
            WHEN dfm.drop_reason = 135 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 136 THEN 'Concorrência'
            WHEN dfm.drop_reason = 137 THEN 'Cliente 5A'
            WHEN dfm.drop_reason = 138 THEN 'Problema Jurídico/Financeiro'
            WHEN dfm.drop_reason = 139 THEN 'Problema Jurídico/Financeiro'
            WHEN dfm.drop_reason = 140 THEN 'Problema Jurídico/Financeiro'
            WHEN dfm.drop_reason = 141 THEN 'Desistência'
            WHEN dfm.drop_reason = 142 THEN 'Desistência'
            WHEN dfm.drop_reason = 143 THEN 'Negociação'
            WHEN dfm.drop_reason = 144 THEN 'Negociação'
            WHEN dfm.drop_reason = 145 THEN 'Negociação'
            WHEN dfm.drop_reason = 146 THEN 'Erro 5A/SL'
            WHEN dfm.drop_reason = 147 THEN 'Desistência'
            WHEN dfm.drop_reason = 148 THEN 'Concorrência'
            WHEN dfm.drop_reason = 149 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 150 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 151 THEN 'Modelo 5A'
            WHEN dfm.drop_reason = 1 THEN 'Fora do Modelo'
            WHEN dfm.drop_reason = 2 THEN 'Fora do Modelo'
            WHEN dfm.drop_reason = 3 THEN 'Fora do Modelo'
            WHEN dfm.drop_reason = 4 THEN 'Falta de Recursos'
            WHEN dfm.drop_reason = 5 THEN 'Fora do Modelo'
            WHEN dfm.drop_reason = 7 THEN 'Negociação'
            WHEN dfm.drop_reason = 8 THEN 'SLA'
            WHEN dfm.drop_reason = 9 THEN 'Baixo intent'
            WHEN dfm.drop_reason = 10 THEN 'Baixo intent'
            WHEN dfm.drop_reason = 11 THEN 'SLA'
            WHEN dfm.drop_reason = 12 THEN 'Negociação'
            WHEN dfm.drop_reason = 13 THEN 'SLA'
            WHEN dfm.drop_reason = 14 THEN 'Negociação'
            WHEN dfm.drop_reason = 15 THEN 'Concorrência'
            WHEN dfm.drop_reason = 16 THEN 'Documentação'
            WHEN dfm.drop_reason = 17 THEN 'Documentação'
            WHEN dfm.drop_reason = 18 THEN 'Concorrência'
            WHEN dfm.drop_reason = 19 THEN 'SLA'
            WHEN dfm.drop_reason = 20 THEN 'SLA'
            WHEN dfm.drop_reason = 102 THEN 'Baixo intent'
            WHEN dfm.drop_reason = 103 THEN 'SLA'
            WHEN dfm.drop_reason = 104 THEN 'Fora do Modelo'
            WHEN dfm.drop_reason = 105 THEN 'Baixo intent'
            WHEN dfm.drop_reason = 106 THEN 'Baixo intent'
            WHEN dfm.drop_reason = 107 THEN 'Falta de Recursos'
            WHEN dfm.drop_reason = 108 THEN 'Erro de Cadastro'
            WHEN dfm.drop_reason = 109 THEN 'Erro de Cadastro'
            WHEN dfm.drop_reason = 110 THEN 'Liquidez'
            WHEN dfm.drop_reason = 111 THEN 'Liquidez'
            WHEN dfm.drop_reason = 112 THEN 'Documentação'
            WHEN dfm.drop_reason = 113 THEN 'Falta de Recursos'
            WHEN dfm.drop_reason = 114 THEN 'Negociação'
            WHEN dfm.drop_reason = 115 THEN 'Falta de Recursos'
            WHEN dfm.drop_reason = 116 THEN 'Baixo intent'
            WHEN dfm.drop_reason = 117 THEN 'Outros'
            WHEN dfm.drop_reason = 118 THEN 'Outros'
            WHEN dfm.drop_reason = 119 THEN 'Outros'
            ELSE 'ERRO'
        END AS drop_subcategory,
        CASE
            WHEN dfm.drop_reason IS NULL AND dfm.dt_offer_dismissed IS NULL THEN ''
            WHEN dfm.drop_reason = 120 THEN 'Buyer'
            WHEN dfm.drop_reason = 121 THEN 'Buyer'
            WHEN dfm.drop_reason = 122 THEN 'Buyer'
            WHEN dfm.drop_reason = 123 THEN 'Buyer'
            WHEN dfm.drop_reason = 124 THEN 'Buyer'
            WHEN dfm.drop_reason = 125 THEN 'Buyer'
            WHEN dfm.drop_reason = 126 THEN 'Buyer'
            WHEN dfm.drop_reason = 127 THEN 'Buyer'
            WHEN dfm.drop_reason = 128 THEN 'Buyer'
            WHEN dfm.drop_reason = 129 THEN 'Buyer'
            WHEN dfm.drop_reason = 130 THEN 'Buyer'
            WHEN dfm.drop_reason = 131 THEN 'Buyer'
            WHEN dfm.drop_reason = 132 THEN 'Buyer'
            WHEN dfm.drop_reason = 133 THEN 'Buyer'
            WHEN dfm.drop_reason = 134 THEN 'Buyer'
            WHEN dfm.drop_reason = 135 THEN 'Buyer'
            WHEN dfm.drop_reason = 136 THEN 'Seller'
            WHEN dfm.drop_reason = 137 THEN 'Seller'
            WHEN dfm.drop_reason = 138 THEN 'Seller'
            WHEN dfm.drop_reason = 139 THEN 'Seller'
            WHEN dfm.drop_reason = 140 THEN 'Seller'
            WHEN dfm.drop_reason = 141 THEN 'Seller'
            WHEN dfm.drop_reason = 142 THEN 'Seller'
            WHEN dfm.drop_reason = 143 THEN 'Seller'
            WHEN dfm.drop_reason = 144 THEN 'Seller'
            WHEN dfm.drop_reason = 145 THEN 'Seller'
            WHEN dfm.drop_reason = 146 THEN 'Seller'
            WHEN dfm.drop_reason = 147 THEN 'Seller'
            WHEN dfm.drop_reason = 148 THEN 'Seller'
            WHEN dfm.drop_reason = 149 THEN 'Seller'
            WHEN dfm.drop_reason = 150 THEN 'Seller'
            WHEN dfm.drop_reason = 151 THEN 'Seller'
            WHEN dfm.drop_reason = 1 THEN 'Buyer'
            WHEN dfm.drop_reason = 2 THEN 'Buyer'
            WHEN dfm.drop_reason = 3 THEN 'Buyer'
            WHEN dfm.drop_reason = 4 THEN 'Buyer'
            WHEN dfm.drop_reason = 5 THEN 'Buyer'
            WHEN dfm.drop_reason = 7 THEN 'Buyer'
            WHEN dfm.drop_reason = 8 THEN 'Buyer'
            WHEN dfm.drop_reason = 9 THEN 'Buyer'
            WHEN dfm.drop_reason = 10 THEN 'Buyer'
            WHEN dfm.drop_reason = 11 THEN 'Buyer'
            WHEN dfm.drop_reason = 12 THEN 'Seller'
            WHEN dfm.drop_reason = 13 THEN 'Buyer'
            WHEN dfm.drop_reason = 14 THEN 'Seller'
            WHEN dfm.drop_reason = 15 THEN 'Buyer'
            WHEN dfm.drop_reason = 16 THEN 'Seller'
            WHEN dfm.drop_reason = 17 THEN 'Seller'
            WHEN dfm.drop_reason = 18 THEN 'Seller'
            WHEN dfm.drop_reason = 19 THEN 'Seller'
            WHEN dfm.drop_reason = 20 THEN 'Seller'
            WHEN dfm.drop_reason = 102 THEN 'Seller'
            WHEN dfm.drop_reason = 103 THEN 'Seller'
            WHEN dfm.drop_reason = 104 THEN 'Seller'
            WHEN dfm.drop_reason = 105 THEN 'Seller'
            WHEN dfm.drop_reason = 106 THEN 'Seller'
            WHEN dfm.drop_reason = 107 THEN 'Buyer'
            WHEN dfm.drop_reason = 108 THEN 'Seller'
            WHEN dfm.drop_reason = 109 THEN 'Seller'
            WHEN dfm.drop_reason = 110 THEN 'Buyer'
            WHEN dfm.drop_reason = 111 THEN 'Seller'
            WHEN dfm.drop_reason = 112 THEN 'Buyer'
            WHEN dfm.drop_reason = 113 THEN 'Buyer'
            WHEN dfm.drop_reason = 114 THEN 'Seller'
            WHEN dfm.drop_reason = 115 THEN 'Buyer'
            WHEN dfm.drop_reason = 116 THEN 'Buyer'
            WHEN dfm.drop_reason = 117 THEN 'Buyer'
            WHEN dfm.drop_reason = 118 THEN 'Seller'
            WHEN dfm.drop_reason = 119 THEN 'Definir'
            ELSE 'ERRO'
        END AS deal_breaker,
        CASE
            WHEN drop_category = 'Quali' THEN dfm.dt_offer_dismissed
            ELSE NULL
        END AS dt_offer_dismissed_qualified,
        CASE
            WHEN drop_category = 'Não Quali' THEN dfm.dt_offer_dismissed
            ELSE NULL
        END AS dt_offer_dismissed_unqualified,
        CASE
            WHEN dt_offer_dismissed IS NOT NULL AND dt_accepted IS NULL THEN 'Pré_OA'
            WHEN dt_offer_dismissed < dt_accepted AND dt_accepted IS NOT NULL AND dt_offer_dismissed IS NOT NULL THEN 'Pré_OA'
            WHEN dt_offer_dismissed >= dt_accepted AND dt_accepted IS NOT NULL AND dt_offer_dismissed IS NOT NULL THEN 'Pós_OA'
        END AS step_discard
    FROM
        datalake_firestore_prod.sale_offer AS so
    LEFT JOIN
        datalake_firestore_prod.monday AS dfm
        ON so.id = dfm.id_offer
)
SELECT
   ofu.id_offer,
   id_consultant_adjusted,
   id_closing_specialist,
   name_consultant,
   closing_specialist_email,
   status_type,
   sale_agreement_status,
   drop_reason_name,
   drop_category,
   drop_subcategory,
   deal_breaker,
   step_discard,
   dt_offer_dismissed_qualified,
   dt_offer_dismissed_unqualified,
   is_offer_dismissed,
   CURRENT_TIMESTAMP AS ts_load
FROM
    offer_rules AS ofu
LEFT JOIN
    consultant_prep_rules AS pr
    ON pr.id_offer = ofu.id_offer