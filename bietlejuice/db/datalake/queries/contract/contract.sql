with contract_cancellation_reasons as (
  with max_cancellations as (
    select
       id,
       max(rev) as max_rev
    from datalake_ebdb_raw_prod.contrato_aud
    where status = 'Cancelado'
      and status_mod = true
    group by 1
  )
  select
	max_cancel.id,
	case
	  when  regexp_like(ure.motivo,'Desacordo entre as partes com rela..o a data de vig.ncia')
	    then 'VALIDITY_DATES'
	  when  regexp_like(ure.motivo,'N.o foi poss.vel contactar uma das partes')
	    then 'UNREACHABLE'
	  when  regexp_like(ure.motivo,'Prazo de assinatura expirado')
	    then 'SIG_DEADLINE_EXPIRED'
	  when  regexp_like(ure.motivo,'Inquilino alugou im.vel por fora do 5A')
	    then 'TENANT_RENTING_WITH_OTHER_COMPANY'
	  when  regexp_like(ure.motivo,'Propriet.rio alugou im.vel por fora do 5A')
	    then 'OWNER_RENTING_WITH_OTHER_COMPANY'
	  when  regexp_like(ure.motivo,'Inquilino prefere outro im.vel 5A')
	    then 'TENANT_PREFERS_OTHER'
	  when  regexp_like(ure.motivo,'Propriet.rio prefere outro inquilino 5A')
	    then 'OWNER_PREFERS_OTHER'
	  when  regexp_like(ure.motivo,'Caracter.sticas/informa..es incorretas no an.ncio')
	    then 'INCORRECT_INFO'
	  when  regexp_like(ure.motivo,'Desacordo entre as partes durante negocia..o')
	    then 'DISAGREEMENT'
	  when  regexp_like(ure.motivo,'Inquilino n.o concorda com modelo 5A')
	    then 'TENANT_DOESNT_AGREE'
	  when  regexp_like(ure.motivo,'Propriet.rio n.o concorda com modelo 5A')
	    then 'OWNER_DOESNT_AGREE'
	  when  regexp_like(ure.motivo,'Demora/confus.o durante processo 5A por parte do inquilino')
	    then 'TENANT_DELAY'
	  when  regexp_like(ure.motivo,'Demora/confus.o durante o processo 5A por parte do propriet.rio')
	    then 'OWNER_DELAY'
	  when  regexp_like(ure.motivo,'Houve uma altera..o no valor do im.vel')
	    then 'PRICE_MODIFICATION'
	  when  regexp_like(ure.motivo,'Inquilino comprou um im.vel e desistiu da loca..o')
	    then 'TENANT_BUYING_HOUSE'
	  when  regexp_like(ure.motivo,'Propriet.rio vendeu o im.vel e desistiu da loca..o')
	    then 'OWNER_SELLING_HOUSE'
	  when  regexp_like(ure.motivo,'Inquilino desistiu da loca..o devido a mudan.a ou problema familiar')
	    then 'TENANT_GAVE_UP_RENTING'
	  when  regexp_like(ure.motivo,'Propriet.rio desistiu da loca..o devido a mudan.a ou problema familiar')
	    then 'OWNER_GAVE_UP_RENTING'
	  when  regexp_like(ure.motivo,'Inquilino n.o conseguiu entregar/sair do im.vel atual')
	    then 'TENANT_UNABLE_TO_LEAVE'
	  when  regexp_like(ure.motivo,'Propriet.rio n.o conseguiu entregar/sair do im.vel')
	    then 'OWNER_UNABLE_TO_LEAVE'
	  else 'OTHERS'
	end as cancellation_reason,
	from_unixtime(ure.timestamp/1000) as ts_canceled
from max_cancellations max_cancel
join datalake_ebdb_raw_prod.usuariorevisionentity ure
  on max_cancel.max_rev = ure.id
),
contract_analyst_date as (
  with end_dates as (
    select
      c_aud.id as contract_id,
      c_aud.imovel_id,
      c_aud.rev,
	  cast(regexp_extract(c_aud.datarescisao, '\d{4}-\d{2}-\d{2}') as date) as datarescisao,
	  cast(lag(regexp_extract(c_aud.datarescisao, '\d{4}-\d{2}-\d{2}')) over(partition by c_aud.id order by c_aud.rev) as date) as previous_datarescisao,
      from_unixtime(u.timestamp/1000) as ts_analista,
      c_aud.datarescisao_mod
    from datalake_ebdb_raw_prod.contrato_aud c_aud
    join datalake_ebdb_raw_prod.usuariorevisionentity u
      on c_aud.rev = u.id
  ),
  end_dates_changes as (
    select
  	  ed.contract_id,
	  ed.imovel_id,
      ed.rev,
      row_number() over(partition by ed.contract_id order by ed.ts_analista) as rn,
      count(ed.rev) over(partition by ed.contract_id) as count_changes,
      ed.datarescisao_mod,
      coalesce(ed.ts_analista,  ed.datarescisao) as ts_analista
    from end_dates as ed
    where ed.datarescisao != ed.previous_datarescisao
      or (ed.datarescisao is not null and ed.previous_datarescisao is null)
  )
  select
	c.id,
	edc.ts_analista as ts_analyst_annulment_input
  from datalake_ebdb_raw_prod.contrato c
  join end_dates_changes edc
    on edc.contract_id = c.id
  where edc.rn = 1
    and edc.ts_analista is not null
),
ongoing_contracts as (
	select
		id,
		case when status in ('Ativo','Finalizado')
				and type <> 'DealOnly'
				and current_date >= date(coalesce(coalesce(ts_signed,dt_started),dt_entered))
				and (current_date < dt_termination or dt_termination is null)
				then true
			else false end as is_ongoing_contract
	from datalake_ebdb_clean_prod.contract
	where dt_termination < current_date or dt_termination is null
)
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
  cf.taxaAdministracaoMensal as monthly_administration_fee,
  c.valorCondominio as condo,
  c.iptu_valor as iptu,
  c.tenantServiceFee as tenant_service_fee,
  c.tipoAssinatura as signature_type,
  c.statusClosing as closing_status,
  c.criadoEm as ts_created,
  c.atualizadoEm as ts_updated,
  ccr.ts_canceled,
  ccr.cancellation_reason,
  c.proposta_id as id_proposal,
  c.imovel_id as id_house,
  cad.ts_analyst_annulment_input,
  regexp_extract(cv.versiondisplaycontract,'^v[^_]+') as contract_version,
  coalesce(oc.is_ongoing_contract,false) as is_ongoing_contract
from datalake_ebdb_raw_prod.contrato c
left join contract_cancellation_reasons ccr
  on ccr.id = c.id
left join datalake_ebdb_raw_prod.contratofull cf
    on cf.id = c.id
left join contract_analyst_date cad
	on cad.id = c.id
left join datalake_ebdb_raw_prod.contractversion cv
	on c.contractversion_id = cv.id
left join ongoing_contracts oc
	on c.id = oc.id
;
