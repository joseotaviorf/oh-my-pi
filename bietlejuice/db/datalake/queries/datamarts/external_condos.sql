with apts_iptu_sp AS (
  SELECT DISTINCT
    ea.setor_quadra,
    ea.ano_construcao_corrigido,
    ea.formatted_address,
    ea.numero_imovel,
    ea.complemento_imovel,
    geo.lat,
    geo.lng,
    geo.geocoded_address AS google_formatted_address,
    'SP' as uf,
    'São Paulo' as municipio
  FROM datalake_raw.external_sp_apts AS ea
  LEFT JOIN datalake_raw.sp_houses_geocoded_addresses AS geo
    ON ea.bldg_address_id = geo.bldg_address_id
    WHERE ea.numero_imovel IS NOT NULL 
    AND geo.lat IS NOT NULL AND geo.lat != ''
)
, apts_direct AS (
  SELECT DISTINCT
    NULL as setor_quadra,
    NULL as ano_construcao_corrigido,
    a.formatted_address,
    i.endereco_numero as numero_imovel,
    i.endereco_complemento as complemento_imovel,
    a.lat,
    a.lng,
    a.google_formatted_address,
    i.uf,
    i.municipio
  FROM datalake_raw.external_iptu_owners i
  JOIN datalake_raw.external_iptu_owners_addresses a ON i.direct_id = a.direct_id
  WHERE
    i.endereco_numero IS NOT NULL
    AND a.lat IS NOT NULL AND a.lat != ''
    AND COALESCE(i.proprietario_cpf_cnpj, '') != ''
)
, apts AS (
  SELECT * FROM apts_iptu_sp
  UNION ALL
  SELECT * FROM apts_direct
)
, condos as (
select 
	google_formatted_address,
	lat,
	lng,
	numero_imovel,
	regexp_extract(google_formatted_address, '\d{5}[-]\d{3}') as cep,
	round(avg(cast(ano_construcao_corrigido as bigint)), 0) as ano_construcao_corrigido,
	count(concat(lat,lng)) as num_apts
from apts
group by 1,2,3,4,5
)
, base_cnpj as (
	select 
		max(c.cnpj) as cnpj,
        max(c.telefone_1) as telefone_1,
        max(c.email) as email,
        min(c.razao_social) as razao_social,
		a.google_formatted_address,
		c.cep,
		trim(replace(c.numero, '.', '')) as numero,
		c.uf,
		c.municipio,
		a.lat,
		a.lng
	FROM datalake_raw.cnpj_br_condos c
  	INNER JOIN datalake_raw.cnpj_br_condos_geocoded_addresses a 
  		ON c.hash = a.hash
    group by
        a.google_formatted_address,
        c.cep,
        trim(replace(c.numero, '.', '')),
        c.uf,
        c.municipio,
        a.lat,
        a.lng
)
, bases_externals as (
select
	max(bc.cnpj) as cnpj,
    min(bc.razao_social) as razao_social,
    max(bc.telefone_1) as telefone_1,
    max(bc.email) as email,
	max(c.google_formatted_address) as google_formatted_address,
	cast(c.numero_imovel as bigint) as numero_imovel,
	bc.cep,
	round(avg(c.ano_construcao_corrigido),0) as ano_construcao_corrigido,
	bc.uf,
	bc.municipio,
	c.lat,
	c.lng,
	sum(c.num_apts) as num_apts
from condos c
inner join base_cnpj bc 
	on concat(c.lat, c.lng) = concat(bc.lat, bc.lng)
group by
    cast(c.numero_imovel as bigint),
    bc.cep,
    bc.uf,
    bc.municipio,
    c.lat,
    c.lng
)
, poligonos as (
	SELECT 
		r.*,
		p.polygon AS geometry
	FROM datalake_clean.ods_dim_region r
	LEFT JOIN datalake_ebdb_clean_prod.polygon_region p ON cast(r.sk_region as bigint) = p.id_region
	WHERE level = 'SubRegiao'
)
, cnpj_regions as (
 select 
 	b.lat,
	b.lng,
 	b.cnpj,
	b.razao_social,
	b.telefone_1,
	b.email,
	b.google_formatted_address,
	b.numero_imovel,
	b.cep,
	b.ano_construcao_corrigido,
	b.uf,
	b.municipio,
	b.num_apts,
 	p.sk_region,
 	p.region_code,
 	p.macro_name,
 	p.city_name,
 	p.city_group,
  p.name
 from bases_externals as b
 left join poligonos as p
 ON ST_WITHIN(
      ST_POINT(CAST(b.lng AS double), CAST(b.lat AS DOUBLE)),
      p.geometry
 	)
)
, distinct_url as (
select  
    lat,
    lng,
    url,
    advertiser_name,
    cast(rent as real) as rent,
    cast(condominium as real) as condominium,
    cast(nb_street as bigint) as number_street,
    cast(rent as real) + coalesce(cast(condominium as real),0) + coalesce(cast(iptu as real),0) as total_value,
    max(crawled_on) as last_date
from datalake_clean.crawlers
where business in ('Alugado', 'aluguel', 'RENTAL')
        and (ws = 'vivareal' or website = 'vivareal') 
        and try_cast(crawled_on as date) >= CURRENT_DATE - interval '60' day
        and lat is not null and lng is not null
        and rent is not null
        and 0.2*cast(rent as real) >= cast(iptu as real)
        AND advertiser_name not like '%quinto%andar%'
group by 1,2,3,4,5,6,7,8
)
, n_tile_table as (
select 
    *,
    ntile(30) over (order by rent) as n_rent,
    ntile(30) over (order by condominium) as n_condominium
from distinct_url 
)
, bases_crawlers as (
select 
    lat,
    lng,
    number_street,
    advertiser_name,
    count(distinct url) listings,
    avg(total_value) ticket_medio,
    max(last_date) as last_date
from n_tile_table
where n_rent between 2 and 29 and n_condominium < 30 and number_street is not null
    and number_street is not null
group by 1,2,3,4
)
,  base_external_crawler as (
 select
 	cr.lat,
	cr.lng,
 	cr.sk_region,
 	cr.region_code,
 	cr.macro_name,
 	cr.city_name,
 	cr.city_group,
    cr.name,
 	cr.cnpj,
	cr.razao_social,
	cr.telefone_1,
	cr.email,
	cr.google_formatted_address,
	cr.numero_imovel,
	cr.cep,
	cr.ano_construcao_corrigido,
	cr.uf,
	cr.municipio,
	cr.num_apts,
 	array_distinct(array_agg(bc.advertiser_name)) as r_state,
    sum(bc.listings) as listings,
    sum(listings * ticket_medio) / sum(listings) as avg_rent,
    max(bc.last_date) as last_date
 from cnpj_regions as cr
 left join bases_crawlers as bc
 	on ST_WITHIN(
      	ST_POINT(CAST(cr.lng AS double), CAST(cr.lat AS DOUBLE)),
      	ST_BUFFER(
       	 ST_POINT(CAST(bc.lng AS double), CAST(bc.lat AS DOUBLE)), 0.00045291823
      	)
    )
    and cast(cr.numero_imovel as bigint) = cast(bc.number_street as bigint)
group by
  cr.lat,
  cr.lng,
  cr.sk_region,
  cr.region_code,
  cr.macro_name,
  cr.city_name,
  cr.city_group,
  cr.name,
  cr.cnpj,
  cr.razao_social,
  cr.telefone_1,
  cr.email,
  cr.google_formatted_address,
  cr.numero_imovel,
  cr.cep,
  cr.ano_construcao_corrigido,
  cr.uf,
  cr.municipio,
  cr.num_apts
)
, ongoing as (
select 
    trim(dhl.house_lat) as house_lat, 
    trim(dhl.house_lng) as house_lng, 
    trim(dhl.house_number) as house_number,
    count(distinct case when dhl.house_status = 'alugado' then dhl.id_house end) ongoing_contracts,
    count(distinct case when dhl.house_status = 'publicado' then dhl.id_house end) ongoing_listing,
    avg(cast(nullif(rent,'') as real)) ticket_medio, 
    count(distinct case when dhl.house_status = 'despublicado' then dhl.id_house end) despublicados,
    max(dhl.house_bedrooms) max_bedrooms,
    min(dhl.house_bedrooms) min_bedrooms,
    max(cast(coalesce(nullif(dhl.house_total_area,''),'0') as real)) max_area,
    min(cast(coalesce(nullif(dhl.house_total_area,''),'0') as real)) min_area
from datalake_clean.ods_dim_house_listing  dhl
where dhl.is_last_version = 'True' and cast(dhl.version as bigint) > 0 and trim(house_city) in ('Curitiba','Osasco','Palhoça','Porto Alegre','Rio de Janeiro','Santo André','São Caetano do Sul','São José', 'São Paulo', 'Várzea Paulista')
and dhl.version > '0'
group by 1,2,3
)
, amenities as (
select 
    trim(dhl.house_lat) as house_lat, 
    trim(dhl.house_lng) as house_lng, 
    trim(dhl.house_number) as house_number,
    max(cast(coalesce(nullif(dhl.house_elevator,''),'0') as bigint)) as elevator,
    array_distinct(array_agg(dhl.house_entrance)) doorman,
    array_distinct(array_agg(dhl.key_location)) key_location
from datalake_clean.ods_dim_house_listing  dhl
group by 1,2,3
) 
, leads as (
select 
    trim(dhl.house_lat) as house_lat, 
    trim(dhl.house_lng) as house_lng, 
    trim(dhl.house_number) as house_number,
    count(case when fhlf.sk_conversion_date > '0' then 0 end) as converted_leads,
    count(0) leads
from datalake_clean.ods_fact_house_listing_flows fhlf
join datalake_clean.ods_dim_house_listing  dhl on dhl.sk_house_listing = fhlf.sk_house_listing
join datalake_clean.ods_dim_date dd on fhlf.sk_lead_date = dd.sk_date
where try_cast(dd."date" as date) > current_date - interval '120' day and trim(dhl.house_lat) != '' and trim(dhl.house_lng) != ''
group by 1,2,3
) 
, doormen as (
select 
    trim(dhl.house_lat) as house_lat,
    trim(dhl.house_lng) as house_lng,
    trim(dhl.house_number) as house_number,
    count(case when CAST(dud.sk_user_affiliate AS VARCHAR) > '0' then 0 end) doormen,
    array_agg(distinct du.telefone_principal) as telephone,
    array_agg(distinct du.nome) as name,
    array_agg(distinct du.email) as email
from datalake_clean.ods_fact_house_listing_flows fhlf
join datalake_clean.ods_dim_house_listing dhl on dhl.sk_house_listing = fhlf.sk_house_listing
join datalake_clean.ods_dim_user_doorman dud on dud.sk_user_affiliate = CAST(fhlf.sk_user_lead_affiliate AS INTEGER)
join datalake_clean.ods_dim_user du on du.sk_user = dud.sk_user_affiliate
where du.dadosafiliado_ativo = 1
group by 1,2,3
)
, base_interna as (
select 	
    l.house_lat,
    l.house_lng,
    regexp_extract(l.house_number, '(\d+)') as house_number,
    o.ongoing_contracts,
    o.ongoing_listing,
    o.ticket_medio,
    o.despublicados,
    o.max_bedrooms,
    o.min_bedrooms,
    o.max_area,
    o.min_area,
    a.elevator,
    a.doorman,
    a.key_location,
    l.converted_leads,
    l.leads,
    d.doormen,
    d.name,
    d.telephone,
    d.email
from leads as l 
join amenities a on l.house_lat = a.house_lat 
                       and l.house_lng = a.house_lng 
                       and l.house_number = a.house_number
join ongoing o on l.house_lat = o.house_lat 
                       and l.house_lng = o.house_lng
                       and l.house_number = o.house_number
left join doormen d on l.house_lat = d.house_lat
                       and l.house_lng = d.house_lng
                       and l.house_number = d.house_number                       
)
select
 	bec.lat as lat,
    bec.lng as lng,
    bec.sk_region as sk_region,
    bec.region_code as region_code,
    bec.name as neighborhood,
    bec.macro_name as macro_name,
    bec.city_name as city_name,
    bec.city_group as city_group,
    bec.cnpj as cnpj,
    bec.razao_social as condo_name,
    bec.telefone_1 as telephone,
    bec.email as email,
    bec.google_formatted_address as google_formatted_address,
    bec.numero_imovel as condo_address_number,
    bec.cep as zipcode,
    bec.ano_construcao_corrigido as condo_construction_year,
    bec.uf as uf,
-- bec.municipio as iptu_city,
    bec.num_apts as iptu_quantity_of_apartments,
 	array_agg(bec.r_state) as competitors_advertiser,
 	bec.listings as competitors_listings,
 	bec.avg_rent as competitors_avg_total_value,
    bec.last_date as competitors_listing_last_date,
    sum(bi.ongoing_contracts) as qa_ongoing_contracts,
sum(bi.ongoing_listing) as qa_ongoing_listing,
sum((ongoing_contracts + ongoing_listing) * ticket_medio) / sum(ongoing_contracts + ongoing_listing) as qa_avg_total_value,
sum(bi.despublicados) as qa_unpublished,
min(bi.min_bedrooms) as qa_min_bedrooms,
max(bi.max_bedrooms) as qa_max_bedrooms,
min(bi.min_area) as qa_min_area,
max(bi.max_area) as qa_max_area,
max(bi.elevator) as qa_elevator,
array_agg(coalesce(bi.doorman, array [''])) as qa_entrance,
array_agg(coalesce(bi.key_location, array [''])) as qa_key_location,
sum(bi.converted_leads) as qa_converted_leads_last_120_days,
sum(bi.leads) as qa_leads_last_120_days,
sum(bi.doormen) as qa_doormen,
array_agg(coalesce(bi.name, array [''])) as qa_doormen_name,
array_agg(coalesce(bi.telephone, array [''])) as qa_doormen_telephone,
array_agg(coalesce(bi.email, array [''])) as qa_doormen_email
from base_external_crawler as bec
left join base_interna as bi on ST_WITHIN(
      	ST_POINT(CAST(bec.lng AS double), CAST(bec.lat AS DOUBLE)),
      	ST_BUFFER(
       	 ST_POINT(CAST(bi.house_lng AS double), CAST(bi.house_lat AS DOUBLE)), 0.00045291823
      	)
    )    
    and cast(bec.numero_imovel as varchar) = bi.house_number
group by
  bec.lat,
  bec.lng,
  bec.sk_region,
  bec.region_code,
  bec.name,
  bec.macro_name,
  bec.city_name,
  bec.city_group,
  bec.cnpj,
  bec.razao_social,
  bec.telefone_1,
  bec.email,
  bec.google_formatted_address,
  bec.numero_imovel,
  bec.cep,
  bec.ano_construcao_corrigido,
  bec.uf,
  bec.num_apts,
  bec.listings,
  bec.avg_rent,
  bec.last_date