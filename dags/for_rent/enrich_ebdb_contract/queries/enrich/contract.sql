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
),
tenant_service_fee_opt_out_info as (
  with contract_aud_join_rev as (
    select
      ure.ts_revision,
      c_aud.id_contract,
      c_aud.tenant_service_fee as tenant_service_fee,
      c_aud.rev
    from datalake_ebdb_clean.contract_aud c_aud
    join datalake_ebdb_user.user_revision_entity ure
      on c_aud.rev = ure.id
    where c_aud.mod_tenant_service_fee = true
)
, tenant_service_fee_history as (
    select distinct
      car.id_contract,
      first_value(car.tenant_service_fee) over (partition by car.id_contract order by car.rev rows between unbounded preceding and unbounded following) as first_tenant_service_fee,
      last_value(car.tenant_service_fee) over (partition by car.id_contract order by car.rev rows between unbounded preceding and unbounded following) as last_tenant_service_fee,
      last_value(car.ts_revision) over (partition by car.id_contract order by car.rev rows between unbounded preceding and unbounded following) as dt_last_tenant_service_fee_change
    from contract_aud_join_rev car
)
    select
      sfh.id_contract,
      sfh.dt_last_tenant_service_fee_change
    from tenant_service_fee_history sfh
    where sfh.first_tenant_service_fee != 0
    and sfh.last_tenant_service_fee = 0
),
first_rent AS (
  SELECT DISTINCT
    ca.id_contract,
    FIRST_VALUE(rent) OVER (partition by id_contract ORDER BY rev rows BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) first_rent
  FROM
    datalake_ebdb_clean.contract_aud AS ca
  WHERE
    status_closing = 'ContratoAssinado'
),
terminations AS (
    SELECT
        id_contract,
        status,
        dt_vacancy
    FROM
        datalake_terminator_clean.termination
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_created DESC) = 1
),
tenant_ownership_swap AS (
    SELECT
        id_contract,
        id_previous_user_contract_person,
        ts_ownership_swap
    FROM
        datalake_ebdb_contract.contract_person
    WHERE
        contract_role IN ('tenant', 'dweller')
        AND is_living
        AND id_user_contract_person IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_ownership_swap DESC) = 1
)
SELECT
  c.id,
  ch.id_country,
  c.id_proposal,
  c.id_house,
  ch.country_code,
  c.rent,
  CASE
    WHEN
      c.rent <= 1500 THEN 'LOW'
    WHEN
      c.rent < 2500 THEN 'MEDIUM'
    WHEN
      c.rent >= 2500 THEN 'HIGH'
    ELSE
      'UNDEFINED'
  END AS value_segment,
  fre.first_rent AS first_rent_charged,
  c.billing_day_of_month,
  c.guarantee_type,
  c.type,
  c.status,
  COALESCE(GET_JSON_OBJECT(c.contract_rent_model, '$.rentalAdministrator'), 'QUINTOANDAR') AS rental_administrator,
  c.paying_condo,
  c.responsible_for_condo,
  c.paying_iptu,
  c.responsible_for_iptu,
  c.rental_guarantee_installment,
  c.rental_guarantee_value,
  c.home_insurance_installment,
  c.home_insurance_value,
  c.fist_rent_comission_fee, -- TODO this column name is wrong and must be updated to first_rent_comission_fee
  c.condo_price,
  c.iptu,
  c.tenant_service_fee,
  c.agent_brokerage_share,
  (sfo.id_contract is not null) as is_tenant_service_fee_opt_out,
  dt_last_tenant_service_fee_change as ts_tenant_service_fee_opt_out,
  c.is_exit_inspection_opted_out,
  c.signature_type,
  c.status_closing,
  regexp_extract(cv.version_display_contract, '^v[^_]+', 0) AS contract_version,
  COALESCE(oc.is_ongoing_contract, FALSE) AS is_ongoing_contract,
  cm.is_waiting_to_be_signed,
  cm.is_active_or_ended,
  cm.is_canceled,
  cm.is_ended,
  cm.is_full_service,
  cm.is_deal_only,
  IF(tos.id_previous_user_contract_person IS NULL, FALSE, TRUE) AS has_tenant_ownership_swap,
  fc.monthly_administration_fee,
  ccr.cancellation_reason,
  ccr.ts_canceled,
  aad.ts_analyst_annulment_input,
  c.dt_started,
  c.dt_entered,
  IF(t.status = 'DONE' AND c.dt_termination > DATE('2020-01-07'), t.dt_vacancy, c.dt_termination) AS dt_termination,  -- The date filter is when Terminator became the source for terminations
  c.ts_signed,
  c.ts_expected_termination,
  c.ts_contract_expected_end AS dt_contract_expected_end, -- TODO [ODS] rename col to dt_contract_expected_end in clean
  c.ts_minuta_approved,
  c.ts_created,
  c.ts_updated
FROM
  datalake_ebdb_clean.contract AS c
LEFT JOIN
  contract_cancellation_reason AS ccr
    ON ccr.id_contract = c.id
LEFT JOIN
  contract_analyst_annulment_date AS aad
    ON aad.id_contract = c.id
LEFT JOIN
  ongoing_contracts AS oc
	  ON oc.id_contract = c.id
LEFT JOIN
  contract_metrics AS cm
    ON cm.id_contract = c.id
LEFT JOIN
  datalake_ebdb_clean.contract_version AS cv
	  ON cv.id = c.id_contract_version
LEFT JOIN
  datalake_ebdb_clean.full_contract AS fc
    ON fc.id = c.id
LEFT JOIN
  tenant_service_fee_opt_out_info AS sfo
    ON c.id = sfo.id_contract
LEFT JOIN
  first_rent AS fre
    ON fre.id_contract = c.id
JOIN
  datalake_ebdb_country.house AS ch
    ON ch.id_house = c.id_house
LEFT JOIN
  terminations AS t
    ON t.id_contract = c.id
LEFT JOIN
    tenant_ownership_swap AS tos
        ON tos.id_contract = c.id
