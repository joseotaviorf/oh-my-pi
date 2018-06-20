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
			else false
		end as rental_flg,
		case
			when lower(c.business) in ('venda/aluguel') then true
			else false
		end as sale_flg,
		case
			when array_join(split(lower(c.advertiser_type),' '),'-') in ('b2c','inmobiliaria','p2w') then 'b2c'
			when array_join(split(lower(c.advertiser_type),' '),'-') in ('propietario', 'c2c') then 'c2c'
			when array_join(split(lower(c.advertiser_type),' '),'-') in ('agente') then 'corretor'
			when array_join(split(lower(c.advertiser_type),' '),'-') is null then 'unknown'
			else concat('other-',array_join(split(lower(c.advertiser_type),' '),'-'))
		end as advertiser_type,
		case
			when array_join(split(lower(c.type),' '),'-') in ('apartamento','apartamento-padrão','apartment') then 'apartamento'
			when array_join(split(lower(c.type),' '),'-') in ('casa', 'casa-padrão', 'sobrado', 'two_story_house') then 'casa'
			when array_join(split(lower(c.type),' '),'-') in ('casa-de-condomínio', 'condominium', 'home') then 'casa-condominio'
			when array_join(split(lower(c.type),' '),'-') in ('cobertura', 'penthouse') then 'cobertura'
			when array_join(split(lower(c.type),' '),'-') in ('flat') then 'flat'
			when array_join(split(lower(c.type),' '),'-') in ('kitnet', 'loft', 'studio') then 'loft-studio-kitchenette'
			else concat('other-',array_join(split(lower(c.type),' '),'-'))
		end as listing_type,
		regexp_extract(phones, '.(\d+),.(\d+).*', 1) as primary_phone_number,
	  regexp_extract(phones, '.(\d+),[^0-9]?(\d+).*', 2) as secondary_phone_number,
	  case
	    when price is null or trim(price) = ''
	      then null
	    else cast(price as double)
	  end as price,
	  case
	    when rent is null or trim(rent) = ''
	      then null
	    else cast(rent as double)
	  end as rent,
	  case
	    when condominium is null or trim(condominium) = ''
	      then null
	    else cast(condominium as double)
	  end as condominium,
	  case
	    when iptu is null or trim(iptu) = ''
	      then null
	    else cast(iptu as double)
	  end as iptu,
	  case
	    when total_area is null or trim(total_area) = ''
	      then null
	    else cast(total_area as double)
	  end as total_area,
	  case
	    when useful_area is null or trim(useful_area) = ''
	      then null
	    else cast(useful_area as double)
	  end as useful_area,
	  case
	    when bedrooms is null or trim(bedrooms) = ''
	      then null
	    else cast(cast(bedrooms as real) as smallint)
	  end as bedrooms,
	  case
	    when suites is null or trim(suites) = ''
	      then null
	    else cast(cast(suites as real) as smallint)
	  end as suites,
	  case
	    when toilets is null or trim(toilets) = ''
	      then null
	    else cast(cast(toilets as real) as smallint)
	  end as toilets,
	  case
	    when garages is null or trim(garages) = ''
	      then null
	    else cast(cast(garages as real) as smallint)
	  end as garages,
	  case
	    when year_building is null or year_building = '' or year_building < '1900'
	      then null
	    else cast(cast(year_building as real) as integer)
	  end as year_building,
	  cast(regexp_replace(cep, '\D', '') as varchar) as cep,
		c.street,
		advertiser_name,
		c.neighborhood,
		c.city,
		c.state,
		c.lat,
		c.lng,
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
	website,
	pr.regiao_id as sk_region,
	street,
	neighborhood,
	city,
	state,
	lat,
	lng,
	primary_phone_number,
	secondary_phone_number,
	price,
	rent,
	condominium,
	iptu,
	total_area,
	useful_area,
	bedrooms,
	suites,
	toilets,
	garages,
	year_building,
	cep,
	date_format(dt_last_run, '%Y%m%d') as sk_date_last_run,
	date_format(dt_first_seen, '%Y%m%d') as sk_date_first_seen,
	date_format(dt_last_seen, '%Y%m%d') as sk_date_last_seen,
	(dt_last_seen = dt_last_run) as active,
	date_diff('day', dt_first_seen, dt_last_seen) as days_seen,
	date_diff('day', dt_last_seen, dt_last_run) as days_unseen,
	(last_run - last_run_seen) as runs_unseen,
	rental_flg,
	sale_flg,
	listing_type,
	advertiser_type,
	advertiser_name
from
	base_list bl
left join
  (
    SELECT
      p.*,
      r.cidadeNome as cidade
    FROM datalake_raw.ebdb_poligonoregiao p
    left join (
                select
                  max(pr.id) as id
                from datalake_raw.ebdb_poligonoregiao pr
                left join datalake_raw.ebdb_mapregiao mr on pr.regiao_id = mr.id
                where mr.id is not null
                group by poligono
              ) latest on latest.id = p.id
    left join datalake_raw.ebdb_mapregiao r on r.id = p.regiao_id
    where latest.id is not null
  ) pr
  on ST_Contains(
        ST_GEOMETRY_FROM_TEXT(pr.poligono),
        ST_GEOMETRY_FROM_TEXT(concat('Point(',lng,' ',lat,')'))
      ) = true
where
	bl.id is not null
	and crawl_run = last_run_seen