with listing_versions as (
	select distinct
	cast(lv.sk_house_listing as bigint) as sk_house_listing,
	lv.id_house as house_id,
	cast(regexp_extract(lv.ts_listing_version_start, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as min_version_time,
	cast(regexp_extract(lv.ts_listing_version_end, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as max_version_time,
	cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as publication_date,
	cast(regexp_extract(trim(lv.ts_last_de_publication), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as de_publication_date,
	lv.status as last_status_version, -- last status of this version of the imovel
	lv.house_status as status,  -- status of the imovel today
	lv.house_unpublished_reason,
	--- pricing
	case when lv.house_total_value = '' then NULL else cast(cast(lv.house_total_value as double) as bigint) end as valor_total,
	case when lv.rent = '' then NULL else cast(cast(lv.rent as double) as bigint) end as aluguel,
	case when lv.house_condo = '' then NULL else cast(cast(lv.house_condo as double) as bigint) end as condominio,
	case when lv.house_iptu = '' then NULL else cast(cast(lv.house_iptu as double) as bigint) end as iptu, 
	--- location
	fhl.sk_region as region_id,
	--lv.regiao_sub,
	dr.macro_name as regiao_macro,
	lv.house_city as regiao_cidade,
	dr.short_region_name as estado_nome,
  	lv.house_zipcode as cep,
	lv.house_city as cidade,
	lv.house_complement as complemento,
	lv.house_neighborhood as bairro,
	lv.house_lat as lat,
	lv.house_lng as lng,
	lv.house_address as endereco,
	lv.house_number as numero,
	--- features imovel
	lv.house_bedrooms as numero_quartos,
	lv.house_bathrooms as numero_banheiros,
	lv.house_suites	as numero_suites,
	lv.house_garages as numero_vagas,
	if(lv.is_house_furnished = '1', 1, 0) as mobiliado
    -- i.predictedPrice as pricepred_estimate
	from datalake_clean.ods_dim_house_listing as lv
	join datalake_clean.ods_fact_house_listings as fhl
	on fhl.sk_house_listing = lv.sk_house_listing
    join datalake_clean.ods_dim_region dr on dr.sk_region = fhl.sk_region 
	-- left join price_predictions pp on pp.imovel_id = lv.id
),
first_listing_viz as (
	select
		ep_house_id 		as house_id,
		id_amplitude 		as amplitude_id,
		min(date(ts_event)) as first_event_date
	from
		datalake_amplitude_clean_prod."170698_listing_page_viewed_events"
	where
		cast(year as varchar) || '-' || lpad(cast(month as varchar), 2, '0') between date_format(current_date - interval '498' day, '%Y-%m') and date_format(current_date, '%Y-%m')
	group by
		1,
		2
),
first_schedule_viz as (
	select
		ep_house_id 		as house_id,
		id_amplitude 		as amplitude_id,
		min(date(ts_event)) as first_event_date
	from
		datalake_amplitude_clean_prod."170698_schedule_page_viewed_events"
	where
		cast(year as varchar) || '-' || lpad(cast(month as varchar), 2, '0') between date_format(current_date - interval '498' day, '%Y-%m') and date_format(current_date, '%Y-%m')
	group by
		1,
		2
),
users_listing_viz_per_day as (
	select
	lv.sk_house_listing,
	flv.house_id,
	date(flv.first_event_date) as event_date,
	count(flv.amplitude_id) as count_unique_users
	from first_listing_viz flv
	join listing_versions lv on lv.house_id = trim(flv.house_id)
		and lv.publication_date <= flv.first_event_date
		and coalesce(lv.max_version_time, now()) >= flv.first_event_date
	group by 1, 2, 3
),
users_schedule_viz_per_day as (
	select
	lv.sk_house_listing,
	fsv.house_id,
	date(fsv.first_event_date) as event_date,
	count(fsv.amplitude_id) as count_unique_users
	from first_schedule_viz fsv
	join listing_versions lv on lv.house_id = trim(fsv.house_id)
		and lv.publication_date <= fsv.first_event_date
		and coalesce(lv.max_version_time, now()) >= fsv.first_event_date
	group by 1, 2, 3
),
first_favorite_set as (
	select
		ep_house_id 		as house_id,
		id_amplitude 		as amplitude_id,
		min(date(ts_event)) as first_event_date
	from
		datalake_amplitude_clean_prod."170698_listing_favorite_set_events"
	where
		cast(year as varchar) || '-' || lpad(cast(month as varchar), 2, '0') between date_format(current_date - interval '498' day, '%Y-%m') and date_format(current_date, '%Y-%m')
	group by
		1,
		2
),
users_favorites_per_day as (
	select
	lv.sk_house_listing,
	ffs.house_id,
	date(ffs.first_event_date) as event_date,
	count(ffs.amplitude_id) as count_unique_users
	from first_favorite_set ffs
	join listing_versions lv on lv.house_id = trim(ffs.house_id)
		and lv.publication_date <= ffs.first_event_date
		and coalesce(lv.max_version_time, now()) >= ffs.first_event_date
	group by 1, 2, 3
),
first_discard as (
	select
		ep_house_id 		as house_id,
		id_amplitude 		as amplitude_id,
		min(date(ts_event)) as first_event_date
	from
		datalake_amplitude_clean_prod."170698_listing_discard_confirmed_events"
	where
		cast(year as varchar) || '-' || lpad(cast(month as varchar), 2, '0') between date_format(current_date - interval '498' day, '%Y-%m') and date_format(current_date, '%Y-%m')
	group by
		1,
		2
),
users_discarded_per_day as (
	select
	lv.sk_house_listing,
	fd.house_id,
	date(fd.first_event_date) as event_date,
	count(fd.amplitude_id) as count_unique_users
	from first_discard fd
	join listing_versions lv on lv.house_id = trim(fd.house_id)
		and lv.publication_date <= fd.first_event_date
		and coalesce(lv.max_version_time, now()) >= fd.first_event_date
	group by 1, 2, 3
),
bookings as (
	select
	a.id_house as house_id,
	a.id_visitor,
	min(date(ts_created)) as first_booking
	from datalake_ebdb_clean_prod.booking a
	where a.type = 'Visita'
	group by 1, 2
),
users_bookings_per_day as (
	select
	lv.sk_house_listing,
	b.house_id,
	date(b.first_booking) as booking_date,
	count(b.id_visitor) as count_unique_visitors
	from bookings b
	join listing_versions lv on lv.house_id = cast(b.house_id as varchar)
		and lv.publication_date <= b.first_booking
		and coalesce(lv.max_version_time, now()) >= b.first_booking
	group by 1, 2, 3
),
visits as (
	select
	  a.id_house as house_id,
	  a.id_visitor,
	  min(dt_booking) as first_visit
	from
	  datalake_booking_prod.booking a
	where
	  a.type = 'Visita'
	  and a.is_visit_completed
	group by 1, 2
),
users_visits_per_day as (
	select
	lv.sk_house_listing,
	v.house_id,
	date(v.first_visit) as visit_date,
	count(v.id_visitor) as count_unique_visitors
	from visits v
	join listing_versions lv on cast(lv.house_id as bigint) = v.house_id
		and lv.publication_date <= v.first_visit
		and coalesce(lv.max_version_time, now()) >= v.first_visit
	group by 1, 2, 3
),
offers_merge as ( -- list combinations of imovel, user and offer dates
	select
	id_house,
	id_user,
	date(ts_created) as offer_date
	from datalake_ebdb_clean_prod.pre_proposal
	group by 1, 2, 3
		union all
	select
	id_house,
	id_client as id_user,
	date(cast(case when ts_created != null then ts_created end as timestamp)) as offer_date
	from datalake_ebdb_clean_prod.offer
	group by 1, 2, 3
),
offers as ( -- for each imovel and each user, what is the date of first offer
	select 
	om.id_house,
	id_user,
	min(om.offer_date) as first_offer
	from offers_merge om
	group by 1, 2	
),
users_offers_per_day as ( -- for each apartment and each date, how many first offers are there
	select
	lv.sk_house_listing,
	o.id_house,
	date(o.first_offer) as offer_date,
	count(o.id_user) as count_unique_offerers
	from offers o
	join listing_versions lv on lv.house_id = cast(o.id_house as varchar)
		and lv.publication_date <= o.first_offer
		and coalesce(lv.max_version_time, now()) >= o.first_offer
	group by 1, 2, 3
),
offer_analysis_date as ( -- one line per offer and per status with the date it was first accepted/rejected
  select
    oa.id_offer,
    oa.status,
    min(cast(from_unixtime(cast(ure.ts_revision as double) / 1000) as timestamp)) as _date
  from datalake_ebdb_clean_prod.offer_aud oa
  join datalake_ebdb_clean_prod.user_revision_entity ure
    on oa.rev = ure.id
  where oa.MOD_status = true
    and oa.status in ('Aprovada', 'Rejeitada') 
  group by 1, 2
),
offers_accepted_merge as ( -- list combinations of imovel, user and offer accepted dates
	select
    id_house,
    id_user,
    date(cast(case when ts_approved != null then ts_approved end as timestamp)) as offer_accepted_date
    from datalake_ebdb_clean_prod.pre_proposal
    where ts_approved != null
    -- group by 1, 2, 3
		union all
	select
	id_house,
	id_client,
	oad._date as offer_accepted_date
	from datalake_ebdb_clean_prod.offer eo
    join offer_analysis_date oad on eo.id=oad.id_offer and oad.status='Aprovada'
	-- group by 1, 2, 3
),
offers_accepted as ( -- for each imovel and each user, what is the date of first offer accepted
	select 
	oam.id_house,
	id_user,
	min(oam.offer_accepted_date) as first_offer_accepted
	from offers_accepted_merge oam
	group by 1, 2	
),
users_offers_accepted_per_day as ( -- for each apartment and each date, how many first offers accepted are there?
	select
	lv.sk_house_listing,
	oa.id_house,
	date(oa.first_offer_accepted) as offer_accepted_date,
	count(oa.id_user) as count_unique_offerers_accepted
	from offers_accepted oa
	join listing_versions lv on lv.house_id = cast(oa.id_house as varchar)
		and lv.publication_date <= oa.first_offer_accepted
		and coalesce(lv.max_version_time, now()) >= oa.first_offer_accepted
	group by 1, 2, 3
),
docs_first_sent as (
  select
    cast(f.sk_house_listing as bigint) as sk_house_listing, -- f.sk_house as sk_house_listing, -- cast(lv.sk_house_listing as bigint) as sk_house_listing
    date(regexp_extract(
      case 
        when dt_tenant_first_document_sent is null or dt_tenant_first_document_sent = ''
          then dt_tenant_auto_first_doc_sent
        else dt_tenant_first_document_sent
      end, '\d{4}-\d{2}-\d{2}')) as sent_date,
    count(f.sk_proposal) as docs_sent
  from datalake_clean.ods_dim_proposal dprop
  join datalake_clean.ods_fact_listing_rent_flows f
    on dprop.sk_proposal = f.sk_proposal
  where (dprop.dt_tenant_first_document_sent is not null
      and dprop.dt_tenant_first_document_sent != '')
    or
      (dprop.dt_tenant_auto_first_doc_sent is not null
    and dprop.dt_tenant_auto_first_doc_sent != '')
  group by 1, 2
),
docs_completed as (
  select
    cast(f.sk_house_listing as bigint) as sk_house_listing,
    date(regexp_extract(dt_credit_analysis_init, '\d{4}-\d{2}-\d{2}')) as completed_date,
    count(f.sk_proposal) as docs_completed
  from datalake_clean.ods_dim_proposal dprop
  join datalake_clean.ods_fact_listing_rent_flows f
    on dprop.sk_proposal = f.sk_proposal
  where dprop.dt_credit_analysis_init is not null
    and dprop.dt_credit_analysis_init != ''
  group by 1, 2
),
docs_approved as (
  select
    cast(f.sk_house_listing as bigint) as sk_house_listing,
    date(regexp_extract(dt_credit_analysis_end, '\d{4}-\d{2}-\d{2}')) as approved_date,
    count(f.sk_proposal) as docs_approved
  from datalake_clean.ods_dim_proposal dprop
  join datalake_clean.ods_fact_listing_rent_flows f
    on dprop.sk_proposal = f.sk_proposal
  where dprop.dt_credit_analysis_end is not null
    and dprop.dt_credit_analysis_end != ''
    and dprop.status = 'Aprovada'
  group by 1, 2
),
lv_date_series as (
	select 
	lv.sk_house_listing, 
	lv.house_id,
	date(date_add('day', seq.n, lv.publication_date)) as date
	from listing_versions lv 
	cross join unnest(sequence(0,date_diff('day', lv.publication_date, now()))) seq (n)
	where date_add('day', seq.n, lv.publication_date) <= coalesce(lv.max_version_time, now())
),
imovel_status_rev as (
	select 
	cast(from_unixtime(cast(ure.ts_revision as bigint) / 1000) as timestamp) as rev_ts,
	date(cast(from_unixtime(cast(ure.ts_revision as bigint) / 1000) as timestamp)) as rev_date,
	ia.rev,
	lv.sk_house_listing,
	ia.mod_status,
	ia.mod_rent,
	ia.mod_iptu,
	ia.mod_condo,
	ia.status,
	case when ia.total_value is null then NULL else cast(ia.total_value as bigint) end as total_value,
	case when ia.rent is null then NULL else cast(ia.rent as bigint) end as rent,
	case when ia.condo is null then NULL else cast(ia.condo as bigint) end as condo,
	case when ia.iptu is null then NULL else cast(ia.iptu as bigint) end as iptu
	from datalake_ebdb_clean_prod.house_aud ia
	join datalake_ebdb_clean_prod.user_revision_entity ure on ure.id=ia.rev
	join listing_versions lv on lv.house_id = cast(ia.id_house as varchar) 
		and lv.publication_date <= cast(from_unixtime(cast(ure.ts_revision as bigint) / 1000) as timestamp)
		and coalesce(lv.max_version_time, now()) >= cast(from_unixtime(cast(ure.ts_revision as bigint) / 1000) as timestamp)
),
imovel_max_rev_day as (
	select
	rev_date,
	sk_house_listing,
	max(rev) as max_rev
	from imovel_status_rev isr
	group by 1, 2
),
imovel_status_per_day as (
	select 
	date(isr.rev_ts) as rev_date,
	isr.sk_house_listing,
	max(isr.mod_status) as status_mod,
	max(isr.mod_rent) as aluguel_mod,
	max(isr.mod_iptu) as iptu_mod,
	max(isr.mod_condo) as condominio_mod,
	-- case when (max(isr.status_mod) or max(isr.status) != 'publicado') then 'other' else 'publicado' end as status,
	max(isr_l.status) as last_status_day,
	-- avg(isr.aluguel) as avg_aluguel,
	-- avg(isr.valor_total) as avg_valortotal,
	-- avg(isr.condominio) as avg_condominio,
	-- avg(isr.iptu) as avg_iptu,
	max(isr_l.rent) as last_aluguel,
	max(isr_l.total_value) as last_valortotal
	-- max(isr_l.condominio) as last_condominio,
	-- max(isr_l.iptu) as last_iptu
	from imovel_status_rev isr
	left join imovel_max_rev_day imrd on imrd.rev_date = isr.rev_date and imrd.sk_house_listing = isr.sk_house_listing
	left join imovel_status_rev isr_l on isr_l.rev = imrd.max_rev and isr_l.sk_house_listing = imrd.sk_house_listing
	group by 1, 2
	order by 2, 1
),
counts_per_day_lv as (
	select distinct
	ds.sk_house_listing,
	ds.date,
	lviz.count_unique_users as cnt_listing_views,
	fspd.count_unique_users as cnt_favorite_set,
	dpd.count_unique_users as cnt_discarded,
	sviz.count_unique_users as cnt_schedule_views,
	bks.count_unique_visitors as cnt_bookings,
	uvd.count_unique_visitors as cnt_visits,
	uod.count_unique_offerers as cnt_offers,
	uoad.count_unique_offerers_accepted as cnt_offers_accepted,
    docs_s.docs_sent as cnt_docs_sent,
    docs_c.docs_completed as cnt_docs_completed,
    docs_a.docs_approved as cnt_docs_approved,
	ispd.status_mod,
	ispd.aluguel_mod,
	ispd.iptu_mod,
	ispd.condominio_mod,
	ispd.last_status_day,
	-- ispd.avg_aluguel,
	-- ispd.avg_valortotal,
	-- ispd.avg_condominio,
	-- ispd.avg_iptu,
	ispd.last_aluguel,
	ispd.last_valortotal
	-- ispd.last_condominio,
	-- ispd.last_iptu,
	from lv_date_series ds
	left join users_listing_viz_per_day lviz on lviz.sk_house_listing = ds.sk_house_listing and lviz.event_date = ds.date
	left join users_favorites_per_day fspd on fspd.sk_house_listing = ds.sk_house_listing and fspd.event_date = ds.date
	left join users_discarded_per_day dpd on dpd.sk_house_listing = ds.sk_house_listing and dpd.event_date = ds.date
	left join users_schedule_viz_per_day sviz on sviz.sk_house_listing = ds.sk_house_listing and sviz.event_date = ds.date
	left join users_bookings_per_day bks on bks.sk_house_listing = ds.sk_house_listing and bks.booking_date = ds.date
	left join users_visits_per_day uvd on uvd.sk_house_listing = ds.sk_house_listing and uvd.visit_date = ds.date
	left join users_offers_per_day uod on uod.sk_house_listing = ds.sk_house_listing and uod.offer_date = ds.date
	left join users_offers_accepted_per_day uoad on uoad.sk_house_listing = ds.sk_house_listing and uoad.offer_accepted_date = ds.date
	left join imovel_status_per_day ispd on ispd.sk_house_listing = ds.sk_house_listing and ispd.rev_date = ds.date
	-- left join pets_allowed_per_day papd on papd.sk_house_listing = ds.sk_house_listing and papd.rev_date = ds.date
    left join docs_first_sent docs_s on docs_s.sk_house_listing = ds.sk_house_listing and docs_s.sent_date = ds.date
    left join docs_completed docs_c on docs_c.sk_house_listing = ds.sk_house_listing and docs_c.completed_date = ds.date
    left join docs_approved docs_a on docs_a.sk_house_listing = ds.sk_house_listing and docs_a.approved_date = ds.date
)
select * from counts_per_day_lv
-- where counts_per_day_lv.last_status_verion = 'publicado'
-- order by sk_house_listing, date;
