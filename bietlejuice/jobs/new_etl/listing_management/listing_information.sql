select distinct
	cast(lv.sk_house_listing as bigint) as sk_house_listing,
	cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) as publication_date
	from datalake_clean.ods_dim_house_listing as lv
	where cast(regexp_extract(lv.ts_publication, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) as timestamp) >= date('2017-09-01')