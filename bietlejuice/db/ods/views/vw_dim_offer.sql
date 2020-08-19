--drop view if exists vw_dim_offer;
--create or replace view vw_dim_offer as
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
events_without_id_firestore as (
    select distinct on (id_user, id_house)
        cast(id_user as bigint) as id_user,
        cast(id_house as bigint) as id_house,
        app_type,
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        utm_term,
        branded = 'Branded' as flg_branded
    from
        public.offer_submitted_events
    where
        id_firestore is null
    order by id_user, id_house, ts_event
),
events_with_id_firestore as (
    select distinct on (id_firestore)
        id_firestore,
        app_type,
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        utm_term,
        branded = 'Branded' as flg_branded
    from
        public.offer_submitted_events
    where
        id_firestore is not null
    order by id_firestore, ts_event
),
taxonomy_demand as (
    select distinct on (lower(app_type), lower(utm_source), lower(utm_medium), lower(branded))
		app_type,
        utm_source,
        utm_medium,
        branded = 'Branded' as flg_branded,
        Category as mkt_category,
        Flow as mkt_flow,
        Completion as mkt_completion,
        Channel as mkt_channel,
        Medium as mkt_medium,
        Origin as mkt_origin,
        Source as mkt_source,
        Platform as mkt_platform
	from
		gsheets.taxonomy_demand
	where
		first_update_source = 'Inquilinos'
		and flg_via_reschedule = 0
	order by
		lower(app_type),
		lower(utm_source),
		lower(utm_medium),
		lower(branded),
		id
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
      null::numeric(18,4) as first_rent_offered_by_tenant,
      null::numeric(18,4) as first_rent_offered_by_owner,
      last_rent_value_tenant as last_rent_offered_by_tenant,
      last_rent_value_landlord as last_rent_offered_by_owner,
      p.rejection_reason,
      'Other'::varchar as type,
      false as is_instant_offer
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
      last_offered_rent,
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
	  type,
	  is_instant_offer
   from offer
   window w as (partition by id)
),
cte_offers as (
    select
        *
    from
        new_offer
    union
    select
        *
    from
        old_pre_proposal
),
offer_enriched as(
    select
        o.*,
        case
            when ew.id_firestore is not null then ew.app_type
            else ewo.app_type
        end as app_type,
        case
            when ew.id_firestore is not null then ew.utm_source
            else ewo.utm_source
        end as utm_source,
        case
            when ew.id_firestore is not null then ew.utm_medium
            else ewo.utm_medium
        end as utm_medium,
        case
            when ew.id_firestore is not null then ew.utm_campaign
            else ewo.utm_campaign
        end as utm_campaign,
        case
            when ew.id_firestore is not null then ew.utm_content
            else ewo.utm_content
        end as utm_content,
        case
            when ew.id_firestore is not null then ew.utm_term
            else ewo.utm_term
        end as utm_term,
        case
            when ew.id_firestore is not null then ew.flg_branded
            else ewo.flg_branded
        end as flg_branded
    from
        cte_offers o
    left join
        events_without_id_firestore ewo
            on o.user_id = ewo.id_user
            and o.house_id = ewo.id_house
    left join
        events_with_id_firestore ew
            on o.id_firestore = ew.id_firestore
)
select
    o.*,
    case when td.mkt_flow is null then 'Not Mapped' else td.mkt_category end as mkt_category,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_flow end as mkt_flow,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_completion end as mkt_completion,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_origin end as mkt_origin,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_channel end as mkt_channel,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_medium end as mkt_medium,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_source end as mkt_source,
	case when td.mkt_flow is null then 'Not Mapped' else td.mkt_platform end as mkt_platform
from
    offer_enriched o
left join taxonomy_demand td
    on lower(coalesce(td.app_type,'')) = lower(coalesce(o.app_type,''))
	and lower(coalesce(td.utm_source,'')) = lower(coalesce(o.utm_source,''))
	and lower(coalesce(td.utm_medium,'')) = lower(coalesce(o.utm_medium,''))
	and coalesce(td.flg_branded, False) = coalesce(o.flg_branded, False)
;