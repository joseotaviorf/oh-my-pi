select distinct
    so.id AS id_offer,
    --dfm.id_auto_generated, --AGUARDANDO COLUNA
    so.id_house,
    so.id_buyer,
    concat(concat(so.id_buyer,'_'),so.id_house) as "sk_sale_flow",
    --dfm.id_consultant, -- ID DO PRIMEIRO ANALISTA A TRATAR A OFERTA, CORRETO É O ÚLTIMO
    regexp_replace(regexp_replace(cast(right(replace(dgm.consultor,', antonio.sader@quintoandar.com.br',''), len(replace(dgm.consultor,', antonio.sader@quintoandar.com.br','')) - charindex(', ', replace(dgm.consultor,', antonio.sader@quintoandar.com.br',''))) as varchar),' ',''),',','') as "consultant_gsheets",
    case -- id_consultant_adjusted
        when dfm.id_consultant is null and consultant_gsheets = '' then ''
        when dfm.id_consultant is null and consultant_gsheets is null then ''
        when dfm.id_consultant = '12614540' and consultant_gsheets = '' then '12614540'
        when dfm.id_consultant = '12041621' and consultant_gsheets = '' then '12041621'
        when dfm.id_consultant = '11422663' and consultant_gsheets = '' then '11422663'
        when dfm.id_consultant = '11422665' and consultant_gsheets = 'antonio.sader@quintoandar.com.br,' then '12614540'
        when consultant_gsheets = 'dayse.susan@quintoandar.com.br' then '15520028'
        when consultant_gsheets = 'antonio.sader@quintoandar.com.br' then '11422665'
        when consultant_gsheets = 'ana.moraes@quintoandar.com.br' then '12114276'
        when consultant_gsheets = 'gabriel.zucchini@quintoandar.com.br' then '15265928'
        when consultant_gsheets = 'pedro.faria@quintoandar.com.br' then '15265915'
        when consultant_gsheets = 'MoniqueGadelha' then '16209415'
        when consultant_gsheets = 'renan.rocha@quintoandar.com.br' then '14832753'
        when consultant_gsheets = 'anna.almeida@quintoandar.com.br' then '16243829'
        when consultant_gsheets = 'thomas.silva@quintoandar.com.br' then '14610991'
        when consultant_gsheets = 'TuaniDamaceno' then '15557400'
        when consultant_gsheets = 'jessica.thayse@quintoandar.com.br' then '15265919'
        when consultant_gsheets = 'ThiagoAraújo' then '15429031'
        when consultant_gsheets = 'nataly.maciel@quintoandar.com.br' then '15265925'
        when consultant_gsheets = 'pedro.santos@quintoandar.com.br' then '14832767'
        when consultant_gsheets = 'mariana.boer@quintoandar.com.br' then '12614540'
        when consultant_gsheets = 'bruna.araujo@quintoandar.com.br' then '12041621'
        when consultant_gsheets = 'felipe.calegari@quintoandar.com.br' then '11422663'
        when consultant_gsheets = 'mariana.alves@quintoandar.com.br' then '14832760'
        when consultant_gsheets = 'EmersondeSouzaMeneguel' then '15284501'
        --when dfm.id_consultant > 1 and consultant_gsheets = '' then dfm.id_consultant
        else 'ERRO' end as "id_consultant_adjusted",
    case -- name_consultant
        when id_consultant_adjusted is null then null
        when id_consultant_adjusted = '15520028' then 'Dayse Susan'
        when id_consultant_adjusted = '11422665' then 'Antonio Sader'
        when id_consultant_adjusted = '12114276' then 'Ana Cléo Moraes'
        when id_consultant_adjusted = '15265928' then 'Gabriel Zucchini'
        when id_consultant_adjusted = '15265915' then 'Pedro Guilherme Faria'
        when id_consultant_adjusted = '16209415' then 'Monique Gadelha'
        when id_consultant_adjusted = '14832753' then 'Renan Rocha de Paiva'
        when id_consultant_adjusted = '16243829' then 'Anna Caroline Maia de Almeida'
        when id_consultant_adjusted = '14610991' then 'Thomas Viana da Silva'
        when id_consultant_adjusted = '15557400' then 'Tuani Damaceno'
        when id_consultant_adjusted = '15265919' then 'Jéssica Thayse'
        when id_consultant_adjusted = '15429031' then 'Thiago Araújo'
        when id_consultant_adjusted = '15265925' then 'Nataly Maciel'
        when id_consultant_adjusted = '14832767' then 'Pedro Santos'
        when id_consultant_adjusted = '12614540' then 'Mariana Boer'
        when id_consultant_adjusted = '12041621' then 'Bruna Araujo'
        when id_consultant_adjusted = '11422663' then 'Felipe Calegari da Cunha'
        when id_consultant_adjusted = '14832760' then 'Mariana Montanha Alves'
        when id_consultant_adjusted = '15284501' then 'Emerson de Souza Meneguel'
        else 'ERRO' end as "name_consultant",
    dhl.house_city,
    dfm.status,
    so.status AS status_offer_firestore,
    case -- status_type
        when dfm.status = 'Propostas em validação' then 'Ongoing'
        when dfm.status = 'Propostas Ongoing' then 'Ongoing'
        when dfm.status = 'Propostas Aceitas' then 'Accepted Ongoing'
        when dfm.status = 'Pós CCV' then 'CCV Assinado'
        when dfm.status = 'Compra e Venda Concluídas' then 'CCV Assinado'
        when dfm.status = 'CCV - Cancelado' then 'CCV Assinado'
        when dfm.status = 'Canceladas pós Aceite' then 'Descarte'
        when dfm.status = 'Canceladas em negociação' then 'Descarte'
        when dfm.status = 'Canceladas em validação' then 'Descarte'
        else 'ERRO' end as "status_type",
    dfm.sale_agreement_status,
    dfm.dt_offer_dismissed,
    case when dt_offer_dismissed is not null or dfm.drop_reason is not null then 1 else 0 end as "is_offer_dismissed",
    case -- drop_reason_adjusted
        when dfm.drop_reason is null and dt_offer_dismissed is null then ''
        when len(dfm.drop_reason) > 4 then dfm.drop_reason
        when dfm.drop_reason = 1 then 'Buyer - pagamento envolve permuta'
        when dfm.drop_reason = 2 then 'Buyer - pagamento envolve aluguel investido'
        when dfm.drop_reason = 3 then 'Buyer - pagamento parcelado'
        when dfm.drop_reason = 4 then 'Buyer - não tem dinheiro para a entrada de qualquer imóvel'
        when dfm.drop_reason = 5 then 'Buyer - não aceita modelo 5A'
        when dfm.drop_reason = 7 then 'Buyer - não aceitou a contraproposta do Seller'
        when dfm.drop_reason = 8 then 'Buyer - vai procurar outro imóvel'
        when dfm.drop_reason = 9 then 'Buyer - pediu para desconsiderar a proposta'
        when dfm.drop_reason = 10 then 'Buyer - nunca atende'
        when dfm.drop_reason = 11 then 'Seller - demora para retornar'
        when dfm.drop_reason = 11 then 'Buyer - demora para retornar'
        when dfm.drop_reason = 12 then 'Seller - não aceitou proposta do buyer (sem contraproposta)'
        when dfm.drop_reason = 13 then 'Buyer - desistiu de comprar qualquer imóvel'
        when dfm.drop_reason = 14 then 'Seller - não aceitou contraproposta do buyer'
        when dfm.drop_reason = 15 then 'Buyer - já alugou ou comprou com outra imobiliária'
        when dfm.drop_reason = 16 then 'Seller - problemas de documentação do Imóvel'
        when dfm.drop_reason = 17 then 'Seller - condições legais (que não a documentação do Imóvel)'
        when dfm.drop_reason = 18 then 'Seller - vendeu por outra imobiliária'
        when dfm.drop_reason = 19 then 'Seller - alugou ou vai alugar o imóvel'
        when dfm.drop_reason = 20 then 'Seller - não vai mais vender o imóvel'
        when dfm.drop_reason = 102 then 'Seller - nunca atende'
        when dfm.drop_reason = 103 then 'Seller - demora para retornar'
        when dfm.drop_reason = 104 then 'Seller - não aceita modelo 5A'
        when dfm.drop_reason = 105 then 'Seller - problemas para visitar o imóvel'
        when dfm.drop_reason = 106 then 'Seller - IQ dificultou processo de venda'
        when dfm.drop_reason = 107 then 'Buyer - não tem dinheiro para a entrada (deste imóvel)'
        when dfm.drop_reason = 108 then 'Seller - anúncio com valor incorreto'
        when dfm.drop_reason = 109 then 'Seller - seller é PJ'
        when dfm.drop_reason = 110 then 'Buyer - comprou outro imóvel pelo 5A'
        when dfm.drop_reason = 111 then 'Seller - vendeu pelo 5A para outro buyer'
        when dfm.drop_reason = 112 then 'Buyer - problemas de documentação'
        when dfm.drop_reason = 113 then 'Buyer - financiamento do Buyer não cobre o do Seller'
        when dfm.drop_reason = 114 then 'Seller - não aceita pagamento financiado'
        when dfm.drop_reason = 115 then 'Buyer - desconto maior do que 30%'
        when dfm.drop_reason = 116 then 'Buyer - pediu para desconsiderar a proposta'
        else 'ERRO' end as "drop_reason_name",
    case -- drop_category
        when dfm.drop_reason is null and dt_offer_dismissed is null then ''
        when drop_reason_name = 'Buyer - pediu para desconsiderar a proposta' then 'Não Quali'
        when drop_reason_name = 'Buyer - nunca atende' then 'Não Quali'
        when drop_reason_name = 'Seller - nunca atende' then 'Não Quali'
        when drop_reason_name = 'Buyer - Proposta inválida' then 'Não Quali'
        when drop_reason_name = 'Buyer - Proposta sem visita' then 'Não Quali'
        when drop_reason_name = 'Buyer Não Qualificado' then 'Não Quali'
        when drop_reason_name = 'Imóvel - IQ Morando' then 'Não Quali'
        when drop_reason_name = 'Buyer - problemas de documentação' then 'Não Quali'
        when drop_reason_name = 'Seller - problemas de documentação do Imóvel' then 'Não Quali'
        when drop_reason_name = 'Imóvel - Diligência' then 'Não Quali'
        when drop_reason_name = 'Seller - anúncio com valor incorreto' then 'Não Quali'
        when drop_reason_name = 'Seller - seller é PJ' then 'Não Quali'
        when drop_reason_name = 'Buyer - desconto maior do que 30%' then 'Não Quali'
        when drop_reason_name = 'Buyer - não tem dinheiro para a entrada (deste imóvel)' then 'Não Quali'
        when drop_reason_name = 'Buyer - não tem dinheiro para a entrada de qualquer imóvel' then 'Não Quali'
        when drop_reason_name = 'Buyer - pagamento envolve aluguel investido' then 'Não Quali'
        when drop_reason_name = 'Buyer - pagamento envolve permuta' then 'Não Quali'
        when drop_reason_name = 'Buyer - pagamento parcelado' then 'Não Quali'
        when drop_reason_name = 'Buyer - Condição de Pagamento' then 'Não Quali'
        when drop_reason_name = 'Seller - vendeu pelo 5A para outro buyer' then 'Não Quali'
        when drop_reason_name = 'Seller - IQ dificultou processo de venda' then 'Quali'
        when drop_reason_name = 'Seller - problemas para visitar o imóvel' then 'Quali'
        when drop_reason_name = 'Buyer - já alugou ou comprou com outra imobiliária' then 'Quali'
        when drop_reason_name = 'Seller - vendeu por outra imobiliária' then 'Quali'
        when drop_reason_name = 'Seller - condições legais (que não a documentação do Imóvel)' then 'Quali'
        when drop_reason_name = 'Buyer - financiamento do Buyer não cobre o do Seller' then 'Quali'
        when drop_reason_name = 'Buyer - não aceita modelo 5A' then 'Quali'
        when drop_reason_name = 'Seller - não aceita modelo 5A' then 'Quali'
        when drop_reason_name = 'Buyer - comprou outro imóvel pelo 5A' then 'Quali'
        when drop_reason_name = 'Buyer - não aceitou a contraproposta do Seller' then 'Quali'
        when drop_reason_name = 'Seller - não aceita pagamento financiado' then 'Quali'
        when drop_reason_name = 'Seller - não aceitou contraproposta do buyer' then 'Quali'
        when drop_reason_name = 'Seller - não aceitou proposta do buyer (sem contraproposta)' then 'Quali'
        when drop_reason_name = 'Valor de desconto - Com Contra' then 'Quali'
        when drop_reason_name = 'Valor de desconto - Sem Contra' then 'Quali'
        when drop_reason_name = 'COVID19' then 'Quali'
        when drop_reason_name = 'Buyer - demora para retornar' then 'Quali'
        when drop_reason_name = 'Buyer - desistiu de comprar qualquer imóvel' then 'Quali'
        when drop_reason_name = 'Buyer - vai procurar outro imóvel' then 'Quali'
        when drop_reason_name = 'Seller - alugou ou vai alugar o imóvel' then 'Quali'
        when drop_reason_name = 'Seller - demora para retornar' then 'Quali'
        when drop_reason_name = 'Seller - não vai mais vender o imóvel' then 'Quali'
        when drop_reason_name = 'Buyer desistiu de comprar (esse imóvel)' then 'Quali'
        when drop_reason_name = 'Buyer Expirado - Ainda Procurando' then 'Quali'
        else 'ERRO' end as "drop_category",
    case -- drop_subcategory
        when dfm.drop_reason is null and dt_offer_dismissed is null then ''
        when drop_reason_name = 'Buyer - pediu para desconsiderar a proposta' then 'Baixo intent'
        when drop_reason_name = 'Buyer - nunca atende' then 'Baixo intent'
        when drop_reason_name = 'Seller - nunca atende' then 'Baixo intent'
        when drop_reason_name = 'Buyer - Proposta inválida' then 'Baixo intent'
        when drop_reason_name = 'Buyer - Proposta sem visita' then 'Baixo intent'
        when drop_reason_name = 'Buyer Não Qualificado' then 'Baixo intent'
        when drop_reason_name = 'Imóvel - IQ Morando' then 'Baixo intent'
        when drop_reason_name = 'Buyer - problemas de documentação' then 'Documentação'
        when drop_reason_name = 'Seller - problemas de documentação do Imóvel' then 'Documentação'
        when drop_reason_name = 'Imóvel - Diligência' then 'Documentação'
        when drop_reason_name = 'Seller - anúncio com valor incorreto' then 'Erro de Cadastro'
        when drop_reason_name = 'Seller - seller é PJ' then 'Erro de Cadastro'
        when drop_reason_name = 'Buyer - desconto maior do que 30%' then 'Falta de Recursos'
        when drop_reason_name = 'Buyer - não tem dinheiro para a entrada (deste imóvel)' then 'Falta de Recursos'
        when drop_reason_name = 'Buyer - não tem dinheiro para a entrada de qualquer imóvel' then 'Falta de Recursos'
        when drop_reason_name = 'Buyer - pagamento envolve aluguel investido' then 'Fora do Modelo'
        when drop_reason_name = 'Buyer - pagamento envolve permuta' then 'Fora do Modelo'
        when drop_reason_name = 'Buyer - pagamento parcelado' then 'Fora do Modelo'
        when drop_reason_name = 'Buyer - Condição de Pagamento' then 'Fora do Modelo'
        when drop_reason_name = 'Seller - vendeu pelo 5A para outro buyer' then 'Liquidez'
        when drop_reason_name = 'Seller - IQ dificultou processo de venda' then 'Baixo intent'
        when drop_reason_name = 'Seller - problemas para visitar o imóvel' then 'Baixo intent'
        when drop_reason_name = 'Buyer - já alugou ou comprou com outra imobiliária' then 'Concorrência'
        when drop_reason_name = 'Seller - vendeu por outra imobiliária' then 'Concorrência'
        when drop_reason_name = 'Seller - condições legais (que não a documentação do Imóvel)' then 'Documentação'
        when drop_reason_name = 'Buyer - financiamento do Buyer não cobre o do Seller' then 'Falta de Recursos'
        when drop_reason_name = 'Buyer - não aceita modelo 5A' then 'Fora do Modelo'
        when drop_reason_name = 'Seller - não aceita modelo 5A' then 'Fora do Modelo'
        when drop_reason_name = 'Buyer - comprou outro imóvel pelo 5A' then 'Liquidez'
        when drop_reason_name = 'Buyer - não aceitou a contraproposta do Seller' then 'Negociação'
        when drop_reason_name = 'Seller - não aceita pagamento financiado' then 'Negociação'
        when drop_reason_name = 'Seller - não aceitou contraproposta do buyer' then 'Negociação'
        when drop_reason_name = 'Seller - não aceitou proposta do buyer (sem contraproposta)' then 'Negociação'
        when drop_reason_name = 'Valor de desconto - Com Contra' then 'Negociação'
        when drop_reason_name = 'Valor de desconto - Sem Contra' then 'Negociação'
        when drop_reason_name = 'COVID19' then 'Outros'
        when drop_reason_name = 'Buyer - demora para retornar' then 'SLA'
        when drop_reason_name = 'Buyer - desistiu de comprar qualquer imóvel' then 'SLA'
        when drop_reason_name = 'Buyer - vai procurar outro imóvel' then 'SLA'
        when drop_reason_name = 'Seller - alugou ou vai alugar o imóvel' then 'SLA'
        when drop_reason_name = 'Seller - demora para retornar' then 'SLA'
        when drop_reason_name = 'Seller - não vai mais vender o imóvel' then 'SLA'
        when drop_reason_name = 'Buyer desistiu de comprar (esse imóvel)' then 'SLA'
        when drop_reason_name = 'Buyer Expirado - Ainda Procurando' then 'SLA'
        else 'ERRO' end as "drop_subcategory",
   case -- deal_breaker
        when drop_reason is null and dt_offer_dismissed is null then ''
        when drop_reason_name = 'ERRO' then 'ERRO'
        when drop_reason_name = 'Valor de desconto - Sem Contra' then 'Seller'
        when drop_reason_name = 'Imóvel - Diligência' then 'Seller'
        when drop_reason_name = 'Imóvel - IQ Morando' then 'Seller'
        when drop_reason_name = 'Valor de desconto - Com Contra' then 'Buyer'
        when drop_reason_name = 'Buyer desistiu de comprar (esse imóvel)' then 'Buyer'
        when drop_reason_name = 'Buyer Expirado - Ainda Procurando' then 'Buyer'
        when drop_reason_name = 'Buyer Não Qualificado' then 'Buyer'
        when drop_reason_name = 'COVID19' then 'Outros'
        when drop_reason_name != '' then LEFT(drop_reason_name, CHARINDEX(' - ', drop_reason_name))
        else 'ERRO' end as "deal_breaker",
    case when drop_category = 'Quali' then dfm.dt_offer_dismissed else null end as "dt_offer_dismissed_quali",
    case when drop_category = 'Não Quali' then dfm.dt_offer_dismissed else null end as "dt_offer_dismissed_naoquali",
    dfm.dt_submitted as "dt_offer_submitted",
    least(dfm.dt_deal_qualified,dt_offer_dismissed_quali,dfm.dt_accepted) as "dt_deal_qualified_adjusted",
    dfm.dt_accepted as "dt_offer_accepted",
    dfm.dt_sale_agreement_created,
    --'' as "dt_sale_agreement_submitted", -- AGUARDANDO COLUNA
    dfm.dt_sale_agreement_signed,
    case when dt_offer_dismissed_naoquali is null then 0 when dt_offer_dismissed_naoquali > dt_deal_qualified_adjusted then 1 else 0 end as "erro_deal_quali",
    case
        when is_offer_dismissed = 0 then null
        when dfm.dt_offer_dismissed >= dfm.dt_sale_agreement_signed then 'pós_assinatura_ccv'
        --when dfm.dt_offer_dismissed >= dfm.dt_sale_agreement_submitted then 'pós_envio_ccv' -- AGUARDANDO COLUNA
        when dfm.dt_offer_dismissed >= dfm.dt_sale_agreement_created then 'pós_pedido_confec'
        when dfm.dt_offer_dismissed >= dt_offer_accepted then 'pós_aceite_proposta'
        when dfm.dt_offer_dismissed >= dt_deal_qualified_adjusted then 'pós_deal_quali'
        when dfm.dt_offer_dismissed >= dt_offer_submitted then 'pós_proposta_enviada'
        else 'ERRO' end as "descarte_etapa"
from 
    datalake_firestore_prod.sale_offer so
left join 
    datalake_firestore_prod.monday dfm
        on so.id = dfm.id_offer
left join 
    dim_house_listing dhl 
        on dfm.id_house = dhl.id_house
left join 
    datalake_raw.gsheets_sale_offers_monday dgm 
        on dgm.name = dfm.id_offer
