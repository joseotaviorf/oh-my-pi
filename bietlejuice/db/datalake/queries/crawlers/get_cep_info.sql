-- query to get cep info
-- params: ceps

with input_ceps as (
    select
        t.cep as cep
    from
        unnest(regexp_extract_all('{ceps}', '\d+')) as t(cep)
),
ebdb_ceps as (
    select
        house_address_street_type as tplogradouro,
        house_address_street as logradouro,
        neighborhood as bairro,
        city as cidade,
        state as estado,
        replace(zip_code, '-', '') as cepp
    from
        datalake_ebdb_clean_prod.cep
)
select c1.cep, c2.*
from input_ceps c1
left join ebdb_ceps c2 on c1.cep = c2.cepp
;

