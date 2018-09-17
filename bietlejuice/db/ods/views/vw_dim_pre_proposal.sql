drop view if exists vw_dim_pre_proposal;
create view vw_dim_pre_proposal
as
SELECT
  p.id as sk_pre_proposal,
  p.id as id_pre_proposal,
  p.code as code,
  p.aluguel as renting_value,
  p."aluguelOriginal" as renting_original_value,
  p."condominioOriginal" as condo_original_value,
  p."dataAprovacao" as dt_approved,
  p.edicao as editing,
  p.status,
  p."proprietarioAceitouCondicoes5A" as owner_accepted_5A_conditions,
  p.usuario_id,
  p.imovel_id,
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
  p.other_conditions
FROM
  public.pre_proposal p
left join
(
	select	distinct
		p.id,
		max(p."atualizadoEm") over w as last_updated_date,
		max(a."expirationDate") over w as expiration_date,
		
		max(a.aluguel)  
			filter(where a.edicao = 'EdicaoInquilino' and "aluguel_MOD" = 1) 
			over w 
		as last_rent_value_tenant,
		
		coalesce(
			min(a.aluguel)  filter(where a.edicao = 'EdicaoProprietario' and "aluguel_MOD" = 1) over w 
			,min(a."aluguelOriginal") over w 
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
) pp_aud
on p.id = pp_aud.id
;

--select * from vw_dim_pre_proposal
