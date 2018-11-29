with listing_versions as (
	select distinct
	cast(lv.sk_house_listing as bigint) as sk_house_listing,
	case is_exclusive when 'True' then True else False end as is_exclusive,
	cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as publication_date,
	cast(regexp_extract(trim(lv.ts_publication), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as de_publication_date,
	cast(regexp_extract(lv.listing_category_start, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as min_version_time,
	cast(regexp_extract(lv.listing_category_end, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as max_version_time,
	lv.status
	-- valor total ?
	-- aluguel ?
	-- condo?
	-- iptu ?
	from datalake_clean.ods_dim_house_listing as lv
	where cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) >= date('2017-09-01')
),
contract_signed as (
	select
	lv.sk_house_listing,
	min(date(cast(case when c.dataassinado != '' then c.dataassinado end as timestamp))) as contract_signed
	from datalake_raw.ebdb_contrato c
	join listing_versions lv on lv.sk_house_listing = cast(c.imovel_id as bigint)
		and lv.publication_date <= cast(case when c.dataassinado != '' then c.dataassinado end as timestamp)
		and coalesce(lv.max_version_time, now()) >= cast(case when c.dataassinado != '' then c.dataassinado end as timestamp)
	 	and c.status in ('Finalizado','Ativo')
	group by 1
)
select 
lv.sk_house_listing,
lv.publication_date,
lv.de_publication_date,
cs.contract_signed,
lv.status
from listing_versions lv
left join contract_signed cs on cs.sk_house_listing = lv.sk_house_listing;