drop view if exists vw_dim_contract;
create view vw_dim_contract
as
select
	c.id as sk_contract,
    c.id as id_contract,

    "emailFatura" as email_invoice,
    "valorAluguel" as renting_value,
    "numImovel" as property_number,
    "diaMesCobranca" as day_month_due,
    garantia as guarantee,
    tipo as contract_type,
    status as contract_status,
    "dataCalculoComissaoAfiliado" as dt_calc_affiliate_comission,
    "dataCalculoComissaoCorretor" as dt_calc_agent_comission,
    "dataInicio" as dt_contract_start,
    "dataAssinado" as dt_signature,
    "dataMinutaAprovada" as dt_draft_approved,
    "dataEntrada" as dt_entrance,
    "dataFimContratoPrevisto" as dt_contract_intended_end,
    "dataRescisao" as dt_contract_annulment,
    "nomeBanco" as bank_name,
    "paganteCondominio" as condo_payer,
    "paganteIptu" as iptu_payer,
    "responsavelCondominio" as condo_responsible,
    "responsavelIptu" as iptu_responsible,
    "seguroFianca_parcelas" as rental_insurance_installments ,
    "seguroFianca_valor" as rental_insurance_value ,
    "seguroResidencial_parcelas" as home_insurance_installments,
    "seguroResidencial_valor" as home_insurance_value,
    "taxaComissaoPrimeiroAluguel" as first_rental_comission,
    "valorCondominio" as condo_value,
    "valorIptu" as iptu_value,
    "tipoAssinatura" as signature_type,
    "dataContratoEletronicoEnviado" as dt_send_eletronic_contract,
    "statusClosing" as closing_status,
    "contratoAssinado" as contract_signed,
    "contratoAdministracaoAssinado" as contract_administration_signed,
    "contratoAutorizacaoEntradaAssinado" as contract_authorization_signed,
    "contratoLocacaoAssinado" as contract_renting_signed,
    "dataTrocaTitularidade" as dt_ownership_changed,
	c.proposta_id as id_proposal,
    c."criadoEm" as dt_created,
    c."atualizadoEm" as dt_updated,
    now()::timestamp as dt_timestamp
from
	contract c;


