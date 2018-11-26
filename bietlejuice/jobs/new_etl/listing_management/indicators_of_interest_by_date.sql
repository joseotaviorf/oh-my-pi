with listing_versions as (
	select distinct
	cast(lv.sk_house_listing as bigint) as sk_house_listing,
	lv.id_house as house_id,
	cast(regexp_extract(lv.listing_category_start, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as min_version_time,
	cast(regexp_extract(lv.listing_category_end, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as max_version_time,
	cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as publication_date,
	cast(regexp_extract(trim(lv.ts_de_publication), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as de_publication_date,
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
	if(lv.is_house_furnished = '1', 1, 0) as mobiliado,
    prp.email as prop_email,
    prp.telefoneprincipal as prop_phone1
    -- prp.nome as name,
    -- prp.sexo as gender,
    -- i.predictedPrice as pricepred_estimate
	from datalake_clean.ods_dim_house_listing as lv
	join datalake_clean.ods_fact_house_listings as fhl
	on fhl.sk_house_listing = lv.sk_house_listing
    join datalake_raw.ebdb_usuario prp on prp.id = fhl.sk_owner
    join datalake_clean.ods_dim_region dr on dr.sk_region = fhl.sk_region 
	-- left join price_predictions pp on pp.imovel_id = lv.id
	where cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) >= date('2017-09-01')  
),
contract_signed as (
	select
	lv.sk_house_listing,
	min(date(cast(case when c.dataassinado != '' then c.dataassinado end as timestamp))) as contract_signed
	from datalake_raw.ebdb_contrato c
	join listing_versions lv on lv.house_id = c.imovel_id 
		and lv.publication_date <= cast(case when c.dataassinado != '' then c.dataassinado end as timestamp)
		and coalesce(lv.max_version_time, now()) >= cast(case when c.dataassinado != '' then c.dataassinado end as timestamp)
	 	and c.status in ('Finalizado','Ativo')
	group by 1
),
first_listing_viz as (
	select 
	trim(evt.e_house_id) as house_id,
	trim(evt.amplitude_id) as amplitude_id, 
	min(date(cast(regexp_extract(trim(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp))) as first_event_date
	from datalake_clean.amplitude_events evt
	where trim(evt.et) = 'listing_page_viewed'
	and trim(ym) between date_format(current_date - interval '98' day, '%Y-%m') and date_format(current_date, '%Y-%m') 
	and trim(app) = '170698'
	group by 1, 2
),
first_schedule_viz as (
	select 
	trim(evt.e_house_id) as house_id,
	trim(evt.amplitude_id) as amplitude_id, 
	min(date(cast(regexp_extract(trim(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp))) as first_event_date
	from datalake_clean.amplitude_events evt
	where trim(evt.et) = 'schedule_page_viewed'
	and trim(ym) between date_format(current_date - interval '98' day, '%Y-%m') and date_format(current_date, '%Y-%m') 
	and trim(app) = '170698'
	group by 1, 2
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
	trim(evt.e_house_id) as house_id,
	trim(evt.amplitude_id) as amplitude_id, 
	min(date(cast(regexp_extract(trim(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp))) as first_event_date
	from datalake_clean.amplitude_events evt
	where trim(evt.et) = 'listing_favorite_set'
	and trim(ym) between date_format(current_date - interval '98' day, '%Y-%m') and date_format(current_date, '%Y-%m') 
	and trim(app) = '170698'
	group by 1, 2
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
	trim(evt.e_house_id) as house_id,
	trim(evt.amplitude_id) as amplitude_id, 
	min(date(cast(regexp_extract(trim(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp))) as first_event_date
	from datalake_clean.amplitude_events evt
	where trim(evt.et) = 'listing_discard_confirmed'
	and trim(ym) between date_format(current_date - interval '98' day, '%Y-%m') and date_format(current_date, '%Y-%m') 
	and trim(app) = '170698'
	group by 1, 2
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
	a.imovel_id as house_id,
	a.visitante_id,
	min(date(cast(case when criadoem != '' then criadoem end as timestamp))) as first_booking
	from datalake_raw.ebdb_agendamento a
	where a.tipo = 'Visita'
	group by 1, 2
),
users_bookings_per_day as (
	select
	lv.sk_house_listing,
	b.house_id,
	date(b.first_booking) as booking_date,
	count(b.visitante_id) as count_unique_visitors
	from bookings b
	join listing_versions lv on lv.house_id = b.house_id
		and lv.publication_date <= b.first_booking
		and coalesce(lv.max_version_time, now()) >= b.first_booking
	group by 1, 2, 3
),
visits as (
	select
	a.imovel_id as house_id,
	a.visitante_id,
	min(date(case when data != '' then data end)) as first_visit
	from datalake_raw.ebdb_agendamento a
	where a.tipo = 'Visita'
	and a.fupVisita in ('VaiNegociar','Talvez','NaoGostou','VisitouSozinho')
	group by 1, 2
),
users_visits_per_day as (
	select
	lv.sk_house_listing,
	v.house_id,
	date(v.first_visit) as visit_date,
	count(v.visitante_id) as count_unique_visitors
	from visits v
	join listing_versions lv on lv.house_id = v.house_id
		and lv.publication_date <= v.first_visit
		and coalesce(lv.max_version_time, now()) >= v.first_visit
	group by 1, 2, 3
),
offers_merge as ( -- list combinations of imovel, user and offer dates
	select
	imovel_id as imovel_id,
	usuario_id as user_id,
	date(cast(case when criadoem != '' then criadoem end as timestamp)) as offer_date
	from datalake_raw.ebdb_preproposta
	group by 1, 2, 3
		union all
	select
	house_id as imovel_id,
	client_id as user_id,
	date(cast(case when criadoem != '' then criadoem end as timestamp)) as offer_date
	from datalake_raw.ebdb_offer
	group by 1, 2, 3
),
offers as ( -- for each imovel and each user, what is the date of first offer
	select 
	om.imovel_id as house_id,
	user_id,
	min(om.offer_date) as first_offer
	from offers_merge om
	group by 1, 2	
),
users_offers_per_day as ( -- for each apartment and each date, how many first offers are there
	select
	lv.sk_house_listing,
	o.house_id,
	date(o.first_offer) as offer_date,
	count(o.user_id) as count_unique_offerers
	from offers o
	join listing_versions lv on lv.house_id = o.house_id
		and lv.publication_date <= o.first_offer
		and coalesce(lv.max_version_time, now()) >= o.first_offer
	group by 1, 2, 3
),
offer_analysis_date as ( -- one line per offer and per status with the date it was first accepted/rejected
  select
    oa.id,
    oa.status,
    min(cast(from_unixtime(cast(ure.timestamp as double) / 1000) as timestamp)) as _date
  from datalake_raw.ebdb_offer_aud oa
  join datalake_raw.ebdb_usuariorevisionentity ure
    on oa.rev = ure.id
  where oa.status_MOD = '1'
    and oa.status in ('Aprovada', 'Rejeitada') 
  group by 1, 2
),
offers_accepted_merge as ( -- list combinations of imovel, user and offer accepted dates
	select
    imovel_id as imovel_id,
    usuario_id as user_id,
    date(cast(case when dataaprovacao != '' then dataaprovacao end as timestamp)) as offer_accepted_date
    from datalake_raw.ebdb_preproposta
    where dataaprovacao != ''
    -- group by 1, 2, 3
		union all
	select
	eo.house_id as imovel_id,
	eo.client_id as user_id,
	oad._date as offer_accepted_date
	from datalake_raw.ebdb_offer eo
    join offer_analysis_date oad on eo.id=oad.id and oad.status='Aprovada'
	-- group by 1, 2, 3
),
offers_accepted as ( -- for each imovel and each user, what is the date of first offer accepted
	select 
	oam.imovel_id as house_id,
	user_id,
	min(oam.offer_accepted_date) as first_offer_accepted
	from offers_accepted_merge oam
	group by 1, 2	
),
users_offers_accepted_per_day as ( -- for each apartment and each date, how many first offers accepted are there?
	select
	lv.sk_house_listing,
	oa.house_id,
	date(oa.first_offer_accepted) as offer_accepted_date,
	count(oa.user_id) as count_unique_offerers_accepted
	from offers_accepted oa
	join listing_versions lv on lv.house_id = oa.house_id
		and lv.publication_date <= oa.first_offer_accepted
		and coalesce(lv.max_version_time, now()) >= oa.first_offer_accepted
	group by 1, 2, 3
),
docs_first_sent as (
  select
    cast(f.sk_house as bigint) as sk_house_listing, -- f.sk_house as sk_house_listing, -- cast(lv.sk_house_listing as bigint) as sk_house_listing
    date(regexp_extract(
      case 
        when dt_tenant_first_document_sent is null or dt_tenant_first_document_sent = ''
          then dt_tenant_auto_first_doc_sent
        else dt_tenant_first_document_sent
      end, '\d{4}-\d{2}-\d{2}')) as sent_date,
    count(f.sk_proposal) as docs_sent
  from datalake_clean.ods_dim_proposal dprop
  join datalake_clean.ods_fact_demand f
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
    cast(f.sk_house as bigint) as sk_house_listing,
    date(regexp_extract(dt_credit_analysis_init, '\d{4}-\d{2}-\d{2}')) as completed_date,
    count(f.sk_proposal) as docs_completed
  from datalake_clean.ods_dim_proposal dprop
  join datalake_clean.ods_fact_demand f
    on dprop.sk_proposal = f.sk_proposal
  where dprop.dt_credit_analysis_init is not null
    and dprop.dt_credit_analysis_init != ''
  group by 1, 2
),
docs_approved as (
  select
    cast(f.sk_house as bigint) as sk_house_listing,
    date(regexp_extract(dt_credit_analysis_end, '\d{4}-\d{2}-\d{2}')) as approved_date,
    count(f.sk_proposal) as docs_approved
  from datalake_clean.ods_dim_proposal dprop
  join datalake_clean.ods_fact_demand f
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
	cross join unnest(sequence(0,date_diff('day', date('2017-09-01'), now()))) seq (n)
	where date_add('day', seq.n, lv.publication_date) <= coalesce(lv.max_version_time, now())
),
imovel_status_rev as (
	select 
	cast(from_unixtime(cast(ure.timestamp as bigint) / 1000) as timestamp) as rev_ts,
	date(cast(from_unixtime(cast(ure.timestamp as bigint) / 1000) as timestamp)) as rev_date,
	ia.rev,
	lv.sk_house_listing,
	ia.status_mod = '1' as status_mod,
	ia.aluguel_mod = '1' as aluguel_mod,
	ia.iptu_mod = '1' as iptu_mod,
	ia.condominio_mod = '1' as condominio_mod,
	ia.status,
	case when ia.valortotal = '' then NULL else cast(ia.valortotal as bigint) end as valor_total,
	case when ia.aluguel = '' then NULL else cast(ia.aluguel as bigint) end as aluguel,
	case when ia.condominio = '' then NULL else cast(ia.condominio as bigint) end as condominio,
	case when ia.iptu = '' then NULL else cast(ia.iptu as bigint) end as iptu
	from datalake_raw.ebdb_imovel_aud ia
	join datalake_raw.ebdb_usuario_revision_entity ure on ure.id=ia.rev
	join listing_versions lv on lv.house_id = ia.id 
		and lv.publication_date <= cast(from_unixtime(cast(ure.timestamp as bigint) / 1000) as timestamp)
		and coalesce(lv.max_version_time, now()) >= cast(from_unixtime(cast(ure.timestamp as bigint) / 1000) as timestamp)
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
	max(isr.status_mod) as status_mod,
	max(isr.aluguel_mod) as aluguel_mod,
	max(isr.iptu_mod) as iptu_mod,
	max(isr.condominio_mod) as condominio_mod,
	-- case when (max(isr.status_mod) or max(isr.status) != 'publicado') then 'other' else 'publicado' end as status,
	max(isr_l.status) as last_status_day
	-- avg(isr.aluguel) as avg_aluguel,
	-- avg(isr.valor_total) as avg_valortotal,
	-- avg(isr.condominio) as avg_condominio,
	-- avg(isr.iptu) as avg_iptu,
	-- max(isr_l.aluguel) as last_aluguel,
	-- max(isr_l.valor_total) as last_valortotal,
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
	-- ispd.status,
	ispd.last_status_day
	-- ispd.avg_aluguel,
	-- ispd.avg_valortotal,
	-- ispd.avg_condominio,
	-- ispd.avg_iptu,
	-- ispd.last_aluguel,
	-- ispd.last_valortotal,
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
