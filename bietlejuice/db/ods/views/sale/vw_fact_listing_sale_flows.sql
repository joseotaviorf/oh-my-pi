--drop view if exists sale.vw_fact_listing_sale_flows;
--create or replace view sale.vw_fact_listing_sale_flows as
with _reservation as (
	with max_ids as (
		select
			house_id,
			tenant_id,
			max(id) as id,
			count(1) as reservation_attempts
		from
			public.reservation
		group by
			1, 2
	)
	select
		r1.id,
		r1.created_at as created_at,
		r1.house_id as id_house,
		r1.tenant_id as id_tenant,
		mi.reservation_attempts as reservation_attempts
	from
		public.reservation r1
	join max_ids mi on
		r1.id = mi.id 
),
_fact as (
	select
		hrf.id_house_rent_flow as ods_id,
		coalesce((hrf.id_house || lpad(coalesce(vdh."version"::varchar(3), '1'), 3, '0'))::bigint, -1::bigint) as sk_house_listing,
		hrf.id_house,
		coalesce(to_char(hrf.dt_house_first_listing, 'YYYYMMDD')::integer, -1) as sk_house_first_listing_date,
		coalesce(to_char(vdh.ts_listing_version_start, 'YYYYMMDD')::integer, -1) as sk_house_listing_date,
		vdh.ts_listing_version_start as dt_house_listing,
		coalesce(to_char(vdh.ts_last_de_publication, 'YYYYMMDD')::integer, -1) as sk_house_listing_de_publication_date,
		coalesce(h.regiao_id, -1) as sk_region,
		coalesce(hrf.id_rent_flow, -1) as sk_sale_flow,
		coalesce(hrf.id_booking, -1) as sk_booking,
		coalesce(to_char(hrf.dt_booking_created, 'YYYYMMDD')::integer, -1) as sk_booking_created_date,
		hrf.dt_booking_created,
		coalesce(to_char(hrf.dt_visit, 'YYYYMMDD')::integer, -1) as sk_visit_date,
		hrf.dt_visit,
		hrf.visit_completed as flg_visit_completed,
		hrf.visit_performed as flg_visit_performed,
		coalesce(hrf.id_owner, -1) as sk_owner,
		coalesce(hrf.id_user_agent, -1) as sk_user_agent,
	 	coalesce(hrf.id_client, -1) as sk_client,
	 	hrf.dt_client_sign_up,
		coalesce(hrf.id_visit, -1) as sk_visit,
		hrf.visit_created_from_app as flg_visit_created_from_app,
		hrf.visit_created_type,
		hrf.visit_last_updated_from_app as flg_visit_last_updated_from_app,
		coalesce(to_char(ar.dt_rating, 'YYYYMMDD')::integer, -1) as sk_agent_review_rating_date,
		coalesce(rs.id, -1) as sk_reservation,
		coalesce(to_char(rs.created_at, 'YYYYMMDD')::integer, -1) as sk_reservation_created_date,
		rs.reservation_attempts as reservation_attempts,
		((date_part('day', hrf.dt_visit - hrf.dt_booking_created) * 1440 +
			date_part('hour', hrf.dt_visit - hrf.dt_booking_created) * 60 +
			date_part('minute', hrf.dt_visit - hrf.dt_booking_created)) / 1440.)::numeric(14,2) as days_booking_created_to_visit,
		((date_part('day', hrf.dt_visit - hrf.dt_client_sign_up) * 1440 +
			date_part('hour', hrf.dt_visit - hrf.dt_client_sign_up) * 60 +
			date_part('minute', hrf.dt_visit - hrf.dt_client_sign_up)) / 1440.)::numeric(14,2) as days_user_created_to_visit,
		((date_part('day', hrf.dt_visit - vdh.ts_listing_version_start) * 1440 +
			date_part('hour', hrf.dt_visit - vdh.ts_listing_version_start) * 60 +
			date_part('minute', hrf.dt_visit - vdh.ts_listing_version_start)) / 1440.)::numeric(14,2) as days_house_listing_to_visit,
		case
			when b.status = 'Cancelado' then b.reason_enum
		end as cancellation_reason,
		now()::timestamp as ts_load
	from
		public.house_rent_flow hrf
	join staging.dim_house_listing vdh on
		vdh.id_house = hrf.id_house
		and coalesce(hrf.dt_rent_flow_created, '1900-01-01') between coalesce(vdh.ts_listing_version_start, '1900-01-01') and coalesce(vdh.ts_listing_version_end, now())
		and vdh.is_for_sale::int::boolean
	join public.house h on
		h.id = hrf.id_house
	left join public.agent_review ar on
		hrf.id_booking = ar.id_booking
	left join _reservation rs on
		hrf.id_house = rs.id_house
		and hrf.id_client = id_tenant
		and rs.created_at between coalesce(vdh.ts_listing_version_start, '1900-01-01') and coalesce(vdh.ts_listing_version_end, now())
	left join public.booking b on
		b.id = hrf.id_booking
	where
		b.visit_intent = 'SALE'
),
total as (
	select
		ods_id,
		sk_house_listing,
		sk_house_first_listing_date,
		sk_house_listing_date,
		sk_house_listing_de_publication_date,
		sk_region,
		sk_sale_flow,
		sk_booking,
		sk_booking_created_date,
		sk_visit_date,
		sk_owner,
		sk_user_agent,
		sk_client,
		sk_visit,
		flg_visit_completed,
		flg_visit_performed,
		flg_visit_created_from_app,
		visit_created_type,
		flg_visit_last_updated_from_app,
		days_booking_created_to_visit,
		days_user_created_to_visit,
		days_house_listing_to_visit,
		sk_agent_review_rating_date,
		case
			when (sk_booking_created_date > 0 or sk_booking > 0)
				and flg_visit_completed = 1 then 'visit_completed'
			when (sk_booking_created_date > 0 or sk_booking > 0)
				and flg_visit_completed != 1 then 'visit_booked'
			else null
		end as funnel_step,
		cancellation_reason,
		ts_load
	from
		_fact
)
select
	ods_id,
	sk_house_listing,
	sk_house_first_listing_date,
	sk_house_listing_date,
	sk_house_listing_de_publication_date,
	sk_region,
	sk_sale_flow,
 	sk_booking,
	sk_booking_created_date,
	sk_visit_date,
	sk_owner,
	sk_user_agent,
	sk_client,
	sk_visit,
	sk_agent_review_rating_date,
	flg_visit_completed,
	flg_visit_performed,
	flg_visit_created_from_app,
	visit_created_type,
	flg_visit_last_updated_from_app,
	days_booking_created_to_visit,
	days_user_created_to_visit,
	days_house_listing_to_visit,
	funnel_step,
	case
		when funnel_step = 'visit_completed' then cancellation_reason
		when funnel_step = 'visit_booked' then cancellation_reason
		else 'Not Mapped'
	end as funnel_step_drop_reason,
	ts_load
from
	total
