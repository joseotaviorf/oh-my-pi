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
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(r2o.*)') then 'r2o-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(.*auxiliadorapredial.*)') then 'auxiliadora-predial'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(.*cr.ditoreal.*)') then 'credito-real'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(.*leardi.*)') then 'leardi-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(.*megaflats.*)|(a.a.desouza.*)') then 'mega-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(.*provectum.*)') then 'provectum-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(.*tukunaga.*)') then 'roberto-tukunaga'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(adrianosilva.*)') then 'adriano-silva'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(angloamericana.*)') then 'anglo-americana'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(aquinoeguerra.*)') then 'aquino-e-guerra'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(bauerim.*)') then 'bauer-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(bossanovasotheby.*)') then 'bossa-nova-sotheby'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(camposguimar.esim.veis.*)') then 'campos-guimaraes'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(carlosfranco.*)|(carloshenriquedeoliveirafranco.*)') then 'carlos-franco'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(casamineira.*)') then 'casa-mineira'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(casari.*)') then 'casari-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(caspana.*)|(caspanna.*)') then 'caspana-empreendimentos'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(century21.*)') then 'century-21'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(chimento.*)') then 'chimento-desenvolvimento'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(cmbim.*)') then 'cmb-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(coelhodafonseca.*)') then 'coelho-da-fonseca'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(colonianeg.*)') then 'colonia-negocios'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(denisricardodesousasilvalustosa.*)|(.*s.flats.*)|(fernandoantonioaquino.*)') then 'so-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(edmurim.veis.*)') then 'edmur-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(flats.opaulo.*)|(pedrolu.svasconcelospaes.*)') then 'flat-saopaulo'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(flatseflats.*)|(flats.flats.*)') then 'flats-e-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(flatss.opaulo.*)') then 'flats-saopaulo'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(fmsim.veis.*)') then 'fms-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(gon.alvesim.veis.*)|(gon.alvesconsultoria.*)') then 'gonçalves-imóveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(gua.raim.veis.*)') then 'guaira-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(guarida.*)') then 'guarida-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(houseflats.*)') then 'house-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(imoveislux.*)') then 'imoveis-lux'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(j2m.*)') then 'j2m-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(jaimeadm.*)') then 'jaime-adm'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(kauffmann.*)') then 'kauffmann-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(larim.veis.*)') then 'lar-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(lello.*)') then 'lello-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(localim.veis.*)|(localconsultoria.*)') then 'local-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(lockey.*)') then 'lockey'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(lopes.*)') then 'lopes-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(maiaim.veis.*)') then 'maia-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(manueldeferreiraafonso.*)|(imobiliariapaulista.*)|(alia.aim.*)') then 'imobiliaria-paulista'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(marcelokavaleski.*)') then 'marcelo-kavaleski'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(megaim.veis.*)') then 'mega-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(morata.*)|(moratta.*)') then 'moratta-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(nafneg.*)') then 'naf-negocios'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(nunescons.*)') then 'nunes-consultoria'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(nunesim.veis.*)') then 'nunes-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(ol.mpiahouse.*)') then 'olimpia-house'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(pacheco.*)') then 'pacheco-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(panteraim.veis.*)') then 'pantera-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(pinottiim.veis.*)') then 'pinotti-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(plenitude.*)') then 'plenitude-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(pradogon.alves.*)') then 'prado-goncalves'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(proativa.*)') then 'proativa-imobiliaria'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(quintoandar.*)') then 'quinto-andar'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(r2.*)|(marlivieiramaia.*)') then 'r2-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(rarusflats.*)|(jos.alejandromendez.*)') then 'rarus-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(realup.*)|(.*opendoor.*)|(openneg.*)') then 'real-up'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(rfflats.*)|(maraneideamaralferreiramazzaro.*)') then 'rf-flats'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(schidim.veis.*)') then 'scheid-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(shprime.*)') then 'sh-prime'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(specialim.*)') then 'special-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '^(vidaim.veis.*)') then 'vida-imoveis'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(vrconsultoria.*)|(vrflats.*)') then 'vr-consultoria'
      when regexp_like(lower(replace(trim(advertiser_name),' ','')), '(z.loim.veis)') then 'zelo-imoveis'
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