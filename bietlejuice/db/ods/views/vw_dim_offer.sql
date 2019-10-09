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
      null::bigint as id_godfather,
      null::varchar as id_firestore,
      p.aluguel as last_offered_rent,
      p."aluguelOriginal" as original_rent,
      p."condominioOriginal" as original_condo,
      p.dt_analysis,
      p.edicao as editing,
      p.status,
      p.usuario_id as user_id,
      p.imovel_id as house_id,
      p."criadoEm" as dt_created,
      p."atualizadoEm" as dt_updated,
      now()::timestamp as dt_timestamp,
      p."ultimoUpdateEdicao" > 0 as offer_submitted,
      p."dataPrimerioEnvio" as dt_first_sent,
      pp_aud.last_updated_date,
      pp_aud.expiration_date,
      last_rent_value_tenant as last_rent_offered_by_tenant,
      last_rent_value_landlord as last_rent_offered_by_owner,
      p.rejection_reason,
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
      godfather_id as id_godfather,
      firestore_id as id_firestore,
      last_rent as last_offered_rent,
      original_rent,
      original_condo,
      analysis_date as dt_analysis,
      turn as editing,
      status,
      client_id as user_id,
      house_id,
      criado_em as dt_created,
      atualizado_em as dt_updated,
      now()::timestamp as dt_timestamp,
      last_sent_at is not null as offer_submitted,
      first_sent_at as dt_first_sent,
      atualizado_em as last_update_date,
      expiration_date,
      first_rent_offered_by_tenant,
      first_rent_offered_by_owner,
      last_rent_offered_by_tenant,
      last_rent_offered_by_owner,
      rejection_reason,
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