with crawled_cpfs as (
    select
        abbreviation,
        street_name,
        street_number,
        regexp_extract_all(owners, 'CPF (\d\d\d\.\d\d\d\.\d\d\d-\d\d)', 1) as cpfs
    from
  	    datalake_raw.crawled_cpf
),
structured as (
    select distinct
       t.cpf,
       neo.name,
       cc.abbreviation,
       cc.street_name,
       cc.street_number,
       neo.phone_numbers
    from
	    crawled_cpfs cc
    cross join
	    unnest(cpfs) as t(cpf)
    inner join
	    datalake_raw.neoway_owners neo
        on neo.cpf = regexp_replace(t.cpf, '\.|-', '')
)
select
    s.*
from
	structured s
left join datalake_clean.crawled_cpfs old_t
	on s.cpf = old_t.cpf
	and s.street_name = old_t.street_name
	and s.street_number = cast(old_t.street_number as varchar)
	and date(old_t.dt) < date('{dt}')
where
    old_t.cpf is null
