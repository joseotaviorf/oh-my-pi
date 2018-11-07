select
  c.id,
  c.valorAluguel as rent,
  c.diaMesCobranca as day_month_due,
  c.garantia as guarantee,
  c.tipo as type,
  c.status as status,
  c.dataInicio as dt_start,
  c.dataAssinado as ts_signature,
  c.dataMinutaAprovada as ts_draft_approved,
  c.dataEntrada as dt_entrance,
  c.dataFimContratoPrevisto as dt_intended_end,
  c.dataRescisao as dt_annulment,
  c.paganteCondominio as condo_payer,
  c.responsavelCondominio as condo_responsible,
  c.paganteIptu as iptu_payer,
  c.responsavelIptu as iptu_responsible,
  c.seguroFianca_parcelas as rental_insurance_installments,
  c.seguroFianca_valor as rental_insurance_value,
  c.seguroResidencial_parcelas as home_insurance_installments,
  c.seguroResidencial_valor as home_insurance_value,
  c.taxacomissaoprimeiroaluguel as first_rental_commission,
  c.valorCondominio as condo,
  c.valorIptu as iptu,
  c.tipoAssinatura as signature_type,
  c.statusClosing as closing_status,
  c.criadoEm as ts_created,
  c.atualizadoEm as ts_updated,
  c_reasons.ts_canceled,
  c_reasons.cancellation_reason,
  c.proposta_id as id_proposal,
  c.imovel_id as id_house
from Contrato c
left join (
  select
    max_cancellations.id,
    case
      when ure.motivo regexp 'Desacordo entre as partes com rela..o a data de vig.ncia'
        then 'VALIDITY_DATES'
      when ure.motivo regexp 'N.o foi poss.vel contactar uma das partes'
        then 'UNREACHABLE'
      when ure.motivo regexp 'Prazo de assinatura expirado'
        then 'SIG_DEADLINE_EXPIRED'
      when ure.motivo regexp 'Inquilino alugou im.vel por fora do 5A'
        then 'TENANT_RENTING_WITH_OTHER_COMPANY'
      when ure.motivo regexp 'Propriet.rio alugou im.vel por fora do 5A'
        then 'OWNER_RENTING_WITH_OTHER_COMPANY'
      when ure.motivo regexp 'Inquilino prefere outro im.vel 5A'
        then 'TENANT_PREFERS_OTHER'
      when ure.motivo regexp 'Propriet.rio prefere outro inquilino 5A'
        then 'OWNER_PREFERS_OTHER'
      when ure.motivo regexp 'Caracter.sticas/informa..es incorretas no an.ncio'
        then 'INCORRECT_INFO'
      when ure.motivo regexp 'Desacordo entre as partes durante negocia..o'
        then 'DISAGREEMENT'
      when ure.motivo regexp 'Inquilino n.o concorda com modelo 5A'
        then 'TENANT_DOESNT_AGREE'
      when ure.motivo regexp 'Propriet.rio n.o concorda com modelo 5A'
        then 'OWNER_DOESNT_AGREE'
      when ure.motivo regexp 'Demora/confus.o durante processo 5A por parte do inquilino'
        then 'TENANT_DELAY'
      when ure.motivo regexp 'Demora/confus.o durante o processo 5A por parte do propriet.rio'
        then 'OWNER_DELAY'
      when ure.motivo regexp 'Houve uma altera..o no valor do im.vel'
        then 'PRICE_MODIFICATION'
      when ure.motivo regexp 'Inquilino comprou um im.vel e desistiu da loca..o'
        then 'TENANT_BUYING_HOUSE'
      when ure.motivo regexp 'Propriet.rio vendeu o im.vel e desistiu da loca..o'
        then 'OWNER_SELLING_HOUSE'
      when ure.motivo regexp 'Inquilino desistiu da loca..o devido a mudan.a ou problema familiar'
        then 'TENANT_GAVE_UP_RENTING'
      when ure.motivo regexp 'Propriet.rio desistiu da loca..o devido a mudan.a ou problema familiar'
        then 'OWNER_GAVE_UP_RENTING'
      when ure.motivo regexp 'Inquilino n.o conseguiu entregar/sair do im.vel atual'
        then 'TENANT_UNABLE_TO_LEAVE'
      when ure.motivo regexp 'Propriet.rio n.o conseguiu entregar/sair do im.vel'
        then 'OWNER_UNABLE_TO_LEAVE'
      else 'OTHERS'
    end as cancellation_reason,
    from_unixtime(ure.`timestamp` / 1000) as ts_canceled
  from (
     select
       id,
       max(rev) as max_rev
     from Contrato_AUD
     where status = 'Cancelado'
       and status_mod = '1'
     group by 1
  ) max_cancellations
  join UsuarioRevisionEntity ure
    on max_cancellations.max_rev = ure.id
) c_reasons
  on c_reasons.id = c.id
where date(coalesce(c.criadoEm, '1900-01-01 00:00:00')) <= date('{}')
;