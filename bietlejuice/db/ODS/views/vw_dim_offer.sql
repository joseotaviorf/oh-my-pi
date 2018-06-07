drop view if exists vw_dim_offer;
create or replace view vw_dim_offer as
with pp_aud as (
    select distinct
		p.id,
		max(p."atualizadoEm") over w as last_updated_date,
		max(a."expirationDate") over w as expiration_date,
		max(a.aluguel)
			filter(where a.edicao = 'EdicaoInquilino' and "aluguel_MOD" = 1)
			over w
		as last_rent_value_tenant,
		coalesce(
			min(a.aluguel)  filter(where a.edicao = 'EdicaoProprietario' and "aluguel_MOD" = 1) over w,
			min(a."aluguelOriginal") over w
		)	as last_rent_value_landlord,
		max(a.aluguel)
			filter(where a.edicao = 'EdicaoInquilino' and "aluguel_MOD" = 1) over w
		+	max(a."condominioOriginal") over w
		as total_rent_value
	from
		pre_proposal p
	join
		pre_proposal_aud a
		on p.id = a.id
	window
		w as (partition by p.id)
),
old_pre_proposal as (
    select
      (p.id * 100) + 1 as sk_offer,
      p.id as id_offer,
      p.aluguel as renting_value,
      p."aluguelOriginal" as renting_original_value,
      p."condominioOriginal" as condo_original_value,
      p."dataAprovacao" as dt_approved,
      p.edicao as editing,
      p.status,
      p.usuario_id as user_id,
      p.imovel_id as house_id,
      p."criadoEm" as dt_created,
      p."atualizadoEm" as dt_updated,
      now()::timestamp as dt_timestamp,
      p."ultimoUpdateEdicao" > 0 as offer_submitted,
      p."ultimoUpdateEdicao" as ultimo_update_edicao,
      p."dataPrimerioEnvio" as dt_first_sent,
      pp_aud.last_updated_date,
      pp_aud.expiration_date,
      last_rent_value_tenant,
      last_rent_value_landlord,
      total_rent_value,
      p.rejection_reason,
      p.animais_condition,
      p.quando_vai_mudar_condition,
      p.quem_vai_morar_condition,
      p.special_conditions_count,
      p.remove_conditions,
      p.include_conditions,
      p.maintenance_or_repair_conditions,
      p.replace_or_modify_conditions,
      null::integer as price_conditions,
      p.other_conditions,
      'Other'::varchar as type
    from
      pre_proposal p
    left join pp_aud
        on p.id = pp_aud.id
),
new_offer as (
    select distinct
      (id * 100) + 2 as sk_offer,
      id as id_offer,
      rent as renting_value,
      original_rent as renting_original_value,
      original_condo as condo_original_value,
      case
      	when status = 'Aprovada'
      		then analysis_date
      	else null
      end as dt_approved,
      turn as editing,
      status,
      client_id as user_id,
      house_id,
      criado_em as dt_created,
      atualizado_em as dt_updated,
      now()::timestamp as dt_timestamp,
      last_sent_at is not null as offer_submitted,
      null::integer as ultimo_update_edicao,
      first_sent_at as dt_first_sent,
      atualizado_em as last_update_date,
      expiration_date,
      rent as last_rent_value_tenant,
      rent as last_rent_value_landlord,
      rent + original_condo as total_rent_value,
      rejection_reason,
      0 as animais_condition,
      0 as quando_vai_mudar_condition,
      0 as quem_vai_morar_condition,
      count(topic_type) over w as special_conditions_count,
	    max((topic_type = 'Remove')::integer) over w as remove_conditions,
      max((topic_type = 'Add')::integer) over w as include_conditions,
	    max((topic_type = 'RepairMaintenance')::integer) over w as maintenance_or_repair_conditions,
	    max((topic_type = 'ModifyReplace')::integer) over w as replace_or_modify_conditions,
	    max((topic_type = 'Price')::integer) over w as price_conditions,
	    max((topic_type not in ('Add', 'Remove', 'RepairMaintenance', 'ModifyReplace', 'Price'))::integer) over w as other_conditions,
	    type
   from offer
   window w as (partition by id)
)
select *
from new_offer
union
select *
from old_pre_proposal
;