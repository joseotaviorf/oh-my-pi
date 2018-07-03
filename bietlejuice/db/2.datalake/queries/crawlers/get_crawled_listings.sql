with base_crawls as (
	select distinct
		website,
		started_on,
		dense_rank() over (partition by website order by started_on) as crawl_run
	from
		datalake_raw.crawlers
	where website in ('vivareal', 'zapimoveis')
),
base_list as (
	select
		bc.started_on,
		bc.website,
		c.id,
		case
			when lower(c.business) in ('venda/aluguel','rental','aluguel') then true
			when try(cast(rent as double)) is not null then true
			else false
		end as rental_flg,
		case
			when lower(c.business) in ('venda/aluguel') then true
			when try(cast(price as double)) is not null then true
			else false
		end as sale_flg,
		case
			when array_join(split(lower(c.advertiser_type),' '),'-') in ('b2c','inmobiliaria','p2w','real_estate_company','realestatecompany') then 'b2c'
			when array_join(split(lower(c.advertiser_type),' '),'-') in ('propietario', 'c2c', 'owner') then 'c2c'
			when array_join(split(lower(c.advertiser_type),' '),'-') in ('agente') then 'corretor'
			when array_join(split(lower(c.advertiser_type),' '),'-') in ('unknown', 'accounttype_none') then 'unknown'
			when array_join(split(lower(c.advertiser_type),' '),'-') is null then 'unknown'
			else concat('other-',array_join(split(lower(c.advertiser_type),' '),'-'))
		end as advertiser_type,
		c.type as listing_type,
		regexp_replace(replace(try(split(phones,',')[1]),'''',''),'\W') as primary_phone_number,
	  regexp_replace(replace(try(split(phones,',')[2]),'''',''),'\W')as secondary_phone_number.
	  try(cast(price as double)) as price,
	  try(cast(rent as double)) as rent,
	  try(cast(condominium as double)) as condominium,
	  try(cast(iptu as double)) as iptu,
	  try(cast(total_area as double)) as total_area,
	  try(cast(useful_area as double)) as useful_area,
	  try(cast(bedrooms as smallint)) as bedrooms,
	  try(cast(suites as smallint)) as suites,
	  try(cast(toilets as smallint)) as toilets,
	  try(cast(garages as smallint)) as garages,
	  try(cast(year_building as smallint)) as year_building,
		advertiser_name,
		case
			when lower(replace(trim(advertiser_name),' ','')) like 'r20%' then 'r2o-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'r2%' then 'r2-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'marlivieiramaia%' then 'r2-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'angloamericana%' then 'anglo-americana'
			when lower(replace(trim(advertiser_name),' ','')) like 'lello%' then 'lello-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'localimóveis%' then 'local-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'localconsultoria%' then 'local-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'lockey%' then 'lockey'
			when lower(replace(trim(advertiser_name),' ','')) like 'fmsimoveis%' then 'fms-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'fmsimóveis%' then 'fms-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'carlosfranco%' then 'carlos-franco'
			when lower(replace(trim(advertiser_name),' ','')) like 'carloshenriquedeoliveirafranco%' then 'carlos-franco'
			when lower(replace(trim(advertiser_name),' ','')) like 'casamineira%' then 'casa-mineira'
			when lower(replace(trim(advertiser_name),' ','')) like 'bossanovasotheby%' then 'bossa-nova-sotheby'
			when lower(replace(trim(advertiser_name),' ','')) like 'camposguimarãesimóveis%' then 'campos-guimaraes'
			when lower(replace(trim(advertiser_name),' ','')) like 'shprime%' then 'sh-prime'
			when lower(replace(trim(advertiser_name),' ','')) like 'olimpiahouse%' then 'olimpia-house'
			when lower(replace(trim(advertiser_name),' ','')) like 'olímpiahouse%' then 'olimpia-house'
			when lower(replace(trim(advertiser_name),' ','')) like 'coelhodafonseca%' then 'coelho-da-fonseca'
			when lower(replace(trim(advertiser_name),' ','')) like 'casari%' then 'casari-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'century21%' then 'century-21'
			when lower(replace(trim(advertiser_name),' ','')) like 'cmbim%' then 'cmb-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'colonianeg%' then 'colonia-negocios'
			when lower(replace(trim(advertiser_name),' ','')) like 'denisricardodesousasilvalustosa%' then 'so-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'plenitude%' then 'plenitude-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'pradogonçalves%' then 'prado-goncalves'
			when lower(replace(trim(advertiser_name),' ','')) like 'chimento%' then 'chimento-desenvolvimento'
			when lower(replace(trim(advertiser_name),' ','')) like 'proativa%' then 'proativa-imobiliaria'
			when lower(replace(trim(advertiser_name),' ','')) like 'scheidimóveis%' then 'scheid-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'panteraimoveis%' then 'pantera-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'panteraimóveis%' then 'pantera-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'pinottiimoveis%' then 'pinotti-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'pinottiimóveis%' then 'pinotti-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'guaridaimóveis%' then 'guarida-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'guaridaimóveis%' then 'guarida-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'guaíraimóveis%' then 'guaira-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'guairaimóveis%' then 'guaira-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'guairaimoveis%' then 'guaira-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'marcelokavaleski%' then 'marcelo-kavaleski'
			when lower(replace(trim(advertiser_name),' ','')) like 'larimoveis%' then 'lar-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'larimóveis%' then 'lar-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'zeloimóveis%' then 'zelo-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'zêloimóveis%' then 'zelo-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'zeloimóveis%' then 'zelo-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'zeloimoveis%' then 'zelo-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'maiaimóveis%' then 'maia-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'maiaimoveis%' then 'maia-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like '%creditoreal%' then 'credito-real'
			when lower(replace(trim(advertiser_name),' ','')) like '%créditoreal%' then 'credito-real'
			when lower(replace(trim(advertiser_name),' ','')) like 'kauffmann%' then 'kauffmann-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'j2m%' then 'j2m-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'pacheco%' then 'pacheco-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'lopes%' then 'lopes-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like '%provectum%' then 'provectum-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like '%megaflats%' then 'mega-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'aquinoeguerra%' then 'aquino-e-guerra'
			when lower(replace(trim(advertiser_name),' ','')) like 'rfflats%' then 'rf-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'flatssãopaulo%' then 'flats-saopaulo'
			when lower(replace(trim(advertiser_name),' ','')) like 'flatsãopaulo%' then 'flat-saopaulo'
			when lower(replace(trim(advertiser_name),' ','')) like '%sóflats%' then 'so-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'fernandoantonioaquino%' then 'so-flats'
			when lower(replace(trim(advertiser_name),' ','')) like '%leardi%' then 'leardi-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'maraneideamaralferreiramazzaro' then 'rf-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'pedroluísvasconcelospaes' then 'flat-saopaulo'
			when lower(replace(trim(advertiser_name),' ','')) like 'rarusflats%' then 'rarus-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'joséalejandromendez' then 'rarus-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'houseflats%' then 'house-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'quintoandar%' then 'quinto-andar'
			when lower(replace(trim(advertiser_name),' ','')) like '%auxiliadorapredial%' then 'auxiliadora-predial'
			when lower(replace(trim(advertiser_name),' ','')) like 'manueldeferreiraafonso%' then 'imobiliaria-paulista'
			when lower(replace(trim(advertiser_name),' ','')) like 'imobiliariapaulista%' then 'imobiliaria-paulista'
			when lower(replace(trim(advertiser_name),' ','')) like 'aliançaim%' then 'imobiliaria-paulista'
			when lower(replace(trim(advertiser_name),' ','')) like 'aliancaim%' then 'imobiliaria-paulista'
			when lower(replace(trim(advertiser_name),' ','')) like 'caspana%' then 'caspana-empreendimentos'
			when lower(replace(trim(advertiser_name),' ','')) like 'caspanna%' then 'caspana-empreendimentos'
			when lower(replace(trim(advertiser_name),' ','')) like 'flatseflats%' then 'flats-e-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'flats&flats%' then 'flats-e-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'gonçalvesimóveis%' then 'gonçalves-imóveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'gonçalvesconsultoria%' then 'gonçalves-imóveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'imóveislux%' then 'imoveis-lux'
			when lower(replace(trim(advertiser_name),' ','')) like 'jaimeadm%' then 'jaime-adm'
			when lower(replace(trim(advertiser_name),' ','')) like 'vrconsultoria%' then 'vr-consultoria'
			when lower(replace(trim(advertiser_name),' ','')) like 'vrflats%' then 'vr-consultoria'
			when lower(replace(trim(advertiser_name),' ','')) like 'realup%' then 'real-up'
			when lower(replace(trim(advertiser_name),' ','')) like 'opendoor%' then 'real-up'
			when lower(replace(trim(advertiser_name),' ','')) like 'openneg%' then 'real-up'
			when lower(replace(trim(advertiser_name),' ','')) like 'vidaimoveis%' then 'vida-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'vidaimóveis%' then 'vida-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like '%tukunaga%' then 'roberto-tukunaga'
			when lower(replace(trim(advertiser_name),' ','')) like 'edmurimóveis%' then 'edmur-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'morata%' then 'moratta-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'moratta%' then 'moratta-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'specialim%' then 'special-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'megaimóveis%' then 'mega-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'adrianosilva%' then 'adriano-silva'
			when lower(replace(trim(advertiser_name),' ','')) like 'a.a.desouza%' then 'mega-flats'
			when lower(replace(trim(advertiser_name),' ','')) like 'nunesimóveis%' then 'nunes-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'nunesimoveis%' then 'nunes-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'nunescons%' then 'nunes-consultoria'
			when lower(replace(trim(advertiser_name),' ','')) like 'bauerim%' then 'bauer-imoveis'
			when lower(replace(trim(advertiser_name),' ','')) like 'nafneg%' then 'naf-negocios'
			else null
		end as big_advertiser,
		if(round(try(cast(c.lat as double)), 5) = 0, null, round(try(cast(c.lat as double)), 5)) as lat,
		if(round(try(cast(c.lng as double)), 5) = 0, null, round(try(cast(c.lng as double)), 5)) as lng,
		if(c.street = 'Endereço Não Informado' or c.street = '', null, split(c.street, ',')[1]) as street,
		regexp_extract(street, ',?[0-9]+$') as street_number,
		if(c.neighborhood='', null, c.neighborhood) as neighborhood,
		c.city,
		if(c.cep='',null,cep) as cep,
		c.state,
		date(min(c.started_on) over (partition by c.id, c.website)) as dt_first_seen,
		date(max(c.started_on) over (partition by c.id, c.website)) as dt_last_seen,
		date(max(bc.started_on) over (partition by bc.website)) as dt_last_run,
		max(crawl_run) over (partition by bc.website) as last_run,
		max(crawl_run) over (partition by c.id, c.website) as last_run_seen,
		crawl_run
	from
		base_crawls bc
	left join
		datalake_raw.crawlers c
		on bc.website = c.website
		and bc.started_on = c.started_on
)
select
	bl.id,
	bl.website,
	bl.street,
	bl.street_number,
	bl.neighborhood,
	bl.city,
	bl.state,
	bl.lat,
	bl.lng,
	concat(try(cast(bl.lat as varchar)),',',try(cast(bl.lng as varchar))) as latlng,
	array_join(array[bl.street,bl.street_number,bl.neighborhood,bl.city,bl.state],', ') as full_address,
	(bl.street is not null) as street_flg,
	(bl.street_number is not null) as street_number_flg,
	(bl.neighborhood is not null) as neighborhood_flg,
	(bl.cep is not null) as cep_flg,
	(bl.city is not null) as city_flg,
	(bl.lat is not null and bl.lng is not null) as latlng_flg,
	((bl.street is not null) and (bl.street_number is not null) and (bl.neighborhood is not null) and bl.latlng_flg) as full_address_flg,
	bl.primary_phone_number,
	bl.secondary_phone_number,
	bl.price,
	bl.rent,
	bl.condominium,
	bl.iptu,
	bl.total_area,
	bl.useful_area,
	bl.bedrooms,
	bl.suites,
	bl.toilets,
	bl.garages,
	bl.year_building,
	bl.cep,
	cast(date_format(bl.dt_last_run, '%Y%m%d') as integer) as sk_date_last_run,
	cast(date_format(bl.dt_first_seen, '%Y%m%d') as integer) as sk_date_first_seen,
	cast(date_format(bl.dt_last_seen, '%Y%m%d') as integer) as sk_date_last_seen,
	(dt_last_seen = dt_last_run) as active,
	bl.date_diff('day', bl.dt_first_seen, dt_last_seen) as days_seen,
	bl.date_diff('day', bl.dt_last_seen, dt_last_run) as days_unseen,
	(bl.last_run - bl.last_run_seen) as runs_unseen,
	bl.rental_flg,
	bl.sale_flg,
	bl.listing_type,
	bl.advertiser_type,
	bl.big_advertiser,
	bl.advertiser_name,
	(cl.id is not null) as gaddress_flg,
	nullif(cl.glat, '') as glat,
	nullif(cl.glng, '') as glng,
	nullif(cl.gcep, '') as gcep,
	nullif(cl.gstreet, '') as gstreet,
	nullif(cl.gstreet_number, '') as gstreet_number,
	nullif(cl.gneighborhood, '') as gneighborhood,
	nullif(cl.gcity, '') as gcity,
	nullif(cl.gstate, '') as gstate,
	nullif(cl.location_type, '') as location_type,
	nullif(cl.location_precision, '') as location_precision,
	nullif(cl.dt_gaddress, '') as dt_gaddress
from
	base_list bl
left join
	datalake_raw.crawler_locations cl
	on cl.id = bl.id and cl.website = bl.website
where
	bl.id is not null
	and bl.crawl_run = bl.last_run_seen