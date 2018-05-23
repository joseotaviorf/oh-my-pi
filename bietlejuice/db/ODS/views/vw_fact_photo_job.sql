drop view if exists vw_fact_photo_job;
create or replace view vw_fact_photo_job
as
with base_jobs as (
	select
		*,
		row_number() over (partition by imovel_id order by dt_job_created) as rn
	from
		public.photo_job
)
select
	j1.id as id_photo_job,
	((j1.imovel_id || '00') || COALESCE(pl.version, 1))::bigint AS sk_property,
	coalesce(i.regiao_id, -1) as sk_region,
	coalesce(j1.user_cancel_id, -1) as sk_user_cancel,
	coalesce(j1.photographer_id, -1) as sk_user_photographer,
	j1.job_status,
	j1.creation_origin,
	j1.flexible_schedule,
	coalesce(to_char(j1.dt_photographer_accepted::date,'YYYYMMDD')::integer, -1) as sk_date_photographer_accepted,
	coalesce(to_char(j1.dt_job_created::date,'YYYYMMDD')::integer, -1) as sk_date_job_created,
	coalesce(to_char(j1.dt_job_issued::date,'YYYYMMDD')::integer, -1) as sk_date_job_issued,
	coalesce(to_char(j1.dt_shoot_started::date,'YYYYMMDD')::integer, -1) as sk_shoot_started,
	coalesce(to_char(j1.dt_job_scheduled::date,'YYYYMMDD')::integer, -1) as sk_date_job_scheduled,
	coalesce(to_char(j1.dt_photos_uploaded::date,'YYYYMMDD')::integer, -1) as sk_photos_uploaded,
	coalesce(to_char(j1.dt_updated::date,'YYYYMMDD')::integer, -1) as sk_date_updated,
	coalesce(to_char(j1.dt_photographer_start::date,'YYYYMMDD')::integer, -1) as sk_date_photographer_start,
	coalesce(to_char(j1.user_cancel_dt::date,'YYYYMMDD')::integer, -1) as sk_date_user_cancel,
	j1.photo_shoot_contact_name,
	j1.photo_shoot_email,
	j1.photo_shoot_phone,
	j1.photo_shoot_second_phone,
	j1.approved,
	j1.confirmed,
	j1.lockbox,
	j1.key_withdraw,
	j1.key_comments::varchar(100) as key_comments,
	j1.photographer_contract_type,
	j1.job_problem_reason,
	j1.cancel_reason::varchar(100) as cancel_reason,
	(j2 is not null) rescheduled
from
	base_jobs j1
left join
	base_jobs j2
	on j1.imovel_id = j2.imovel_id
	and j1.rn = j2.rn -1
	and j1.dt_job_created + interval '30 day' > j2.dt_job_created
left join
	imovel i
	on i.id = j1.imovel_id
left join
	property_listing pl
	on pl.id = j1.imovel_id
	and j1.dt_job_created between pl.min_version_time and coalesce(pl.max_version_time, current_date)