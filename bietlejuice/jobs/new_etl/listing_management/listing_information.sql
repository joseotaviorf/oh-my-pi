with listing_versions as (
	select distinct
	cast(lv.sk_house_listing as bigint) as sk_house_listing,
	cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as publication_date,
	cast(regexp_extract(trim(lv.de_publication_date), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as de_publication_date
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
	join listing_versions lv on lv.house_id = c.imovel_id 
		and lv.publication_date <= cast(case when c.dataassinado != '' then c.dataassinado end as timestamp)
		and coalesce(lv.max_version_time, now()) >= cast(case when c.dataassinado != '' then c.dataassinado end as timestamp)
	 	and c.status in ('Finalizado','Ativo')
	group by 1
)
select lv.*, cs.contract_signed
from listing_versions lv
left join contract_signed cs on cs.sk_property = lv.sk_property;