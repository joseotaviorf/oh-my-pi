with contract_cancellation_reason as (
  with max_cancellation as (
    select
       id_contract,
       max(rev) as max_rev
    from datalake_ebdb_clean.contract_aud
    where mod_status and status = 'Cancelado'
    group by 1
  )
  select
	mc.id_contract,
	case
	  when ure.reason rlike 'Desacordo entre as partes com rela..o a data de vig.ncia'
	    then 'VALIDITY_DATES'
	  when ure.reason rlike 'N.o foi poss.vel contactar uma das partes'
	    then 'UNREACHABLE'
	  when ure.reason rlike 'Prazo de assinatura expirado'
	    then 'SIG_DEADLINE_EXPIRED'
	  when ure.reason rlike 'Inquilino alugou im.vel por fora do 5A'
	    then 'TENANT_RENTING_WITH_OTHER_COMPANY'
	  when ure.reason rlike 'Propriet.rio alugou im.vel por fora do 5A'
	    then 'OWNER_RENTING_WITH_OTHER_COMPANY'
	  when ure.reason rlike 'Inquilino prefere outro im.vel 5A'
	    then 'TENANT_PREFERS_OTHER'
	  when ure.reason rlike 'Propriet.rio prefere outro inquilino 5A'
	    then 'OWNER_PREFERS_OTHER'
	  when ure.reason rlike 'Caracter.sticas/informa..es incorretas no an.ncio'
	    then 'INCORRECT_INFO'
	  when ure.reason rlike 'Desacordo entre as partes durante negocia..o'
	    then 'DISAGREEMENT'
	  when ure.reason rlike 'Inquilino n.o concorda com modelo 5A'
	    then 'TENANT_DOESNT_AGREE'
	  when ure.reason rlike 'Propriet.rio n.o concorda com modelo 5A'
	    then 'OWNER_DOESNT_AGREE'
	  when ure.reason rlike 'Demora/confus.o durante processo 5A por parte do inquilino'
	    then 'TENANT_DELAY'
	  when ure.reason rlike 'Demora/confus.o durante o processo 5A por parte do propriet.rio'
	    then 'OWNER_DELAY'
	  when ure.reason rlike 'Houve uma altera..o no valor do im.vel'
	    then 'PRICE_MODIFICATION'
	  when ure.reason rlike 'Inquilino comprou um im.vel e desistiu da loca..o'
	    then 'TENANT_BUYING_HOUSE'
	  when ure.reason rlike 'Propriet.rio vendeu o im.vel e desistiu da loca..o'
	    then 'OWNER_SELLING_HOUSE'
	  when ure.reason rlike 'Inquilino desistiu da loca..o devido a mudan.a ou problema familiar'
	    then 'TENANT_GAVE_UP_RENTING'
	  when ure.reason rlike 'Propriet.rio desistiu da loca..o devido a mudan.a ou problema familiar'
	    then 'OWNER_GAVE_UP_RENTING'
	  when ure.reason rlike 'Inquilino n.o conseguiu entregar/sair do im.vel atual'
	    then 'TENANT_UNABLE_TO_LEAVE'
	  when ure.reason rlike 'Propriet.rio n.o conseguiu entregar/sair do im.vel'
	    then 'OWNER_UNABLE_TO_LEAVE'
	  else 'OTHERS'
	end as cancellation_reason,
	from_unixtime(ure.ts_revision/1000) as ts_canceled
from max_cancellation mc
join datalake_ebdb_clean.user_revision_entity ure
  on ure.id = mc.max_rev
),
contract_analyst_annulment_date as (
  with contract_terminations as (
    select
      c_aud.id_contract,
      c_aud.id_house,
      c_aud.rev,
      row_number() over(partition by c_aud.id_contract order by ure.ts_revision) as row_number,
      c_aud.mod_dt_termination,
      c_aud.dt_termination,
      lag(c_aud.dt_termination) over(partition by c_aud.id_contract order by c_aud.rev) as dt_previous_termination,
      from_unixtime(ure.ts_revision/1000) as ts_revision
    from datalake_ebdb_clean.contract_aud c_aud
    join datalake_ebdb_clean.user_revision_entity ure
      on ure.id = c_aud.rev
    where c_aud.mod_dt_termination
  )
    select
      ct.id_contract,
      coalesce(ct.ts_revision,  ct.dt_termination) as ts_analyst_annulment_input
    from contract_terminations as ct
    where ct.row_number = 1
),
contract_metrics(
    select
      id as id_contract,
      status in ('Minuta','PreAssinaturas') as is_waiting_to_be_signed,
      status in ('Ativo','Finalizado') as is_active_or_ended,
      status = 'Cancelado' as is_canceled,
      status = 'Finalizado' as is_ended,
      type = 'FullService' as is_full_service,
      type = 'DealOnly' as is_deal_only
    from datalake_ebdb_clean.contract
),
ongoing_contracts as (
    select
      c.id as id_contract,
      case
        when cm.is_active_or_ended
          and not cm.is_deal_only
          and current_date >= date(coalesce(coalesce(c.ts_signed, c.dt_started), c.dt_entered))
          and (current_date < c.dt_termination or c.dt_termination is null)
          then true
        else false
      end as is_ongoing_contract
    from datalake_ebdb_clean.contract c
    left join contract_metrics cm
        on cm.id_contract = c.id
)
select
  c.id,
  c.id_proposal,
  c.id_house,
  c.rent,
  c.billing_day_of_month,
  c.guarantee_type,
  c.type,
  c.status,
  c.paying_condo,
  c.responsible_for_condo,
  c.paying_iptu,
  c.responsible_for_iptu,
  c.rental_guarantee_installment,
  c.rental_guarantee_value,
  c.home_insurance_installment,
  c.home_insurance_value,
  c.fist_rent_comission_fee,
  c.condo_price,
  c.iptu,
  c.signature_type,
  c.status_closing,
  regexp_extract(cv.version_display_contract, '^v[^_]+', 0) as contract_version,
  coalesce(oc.is_ongoing_contract, false) as is_ongoing_contract,
  cm.is_waiting_to_be_signed,
  cm.is_active_or_ended,
  cm.is_canceled,
  cm.is_ended,
  cm.is_full_service,
  cm.is_deal_only,
  fc.monthly_administration_fee,
  ccr.cancellation_reason,
  ccr.ts_canceled,
  aad.ts_analyst_annulment_input,
  c.dt_started,
  c.dt_entered,
  c.dt_termination,
  c.ts_signed,
  c.ts_contract_expected_end as dt_contract_expected_end, -- TODO [ODS] rename col to dt_contract_expected_end in clean
  c.ts_minuta_approved,
  c.ts_created,
  c.ts_updated
from datalake_ebdb_clean.contract c
left join contract_cancellation_reason ccr
  on ccr.id_contract = c.id
left join contract_analyst_annulment_date aad
  on aad.id_contract = c.id
left join ongoing_contracts oc
	on oc.id_contract = c.id
left join contract_metrics cm
    on cm.id_contract = c.id
left join datalake_ebdb_clean.contract_version cv
	on  cv.id = c.id_contract_version
left join datalake_ebdb_clean.full_contract fc
    on fc.id = c.id