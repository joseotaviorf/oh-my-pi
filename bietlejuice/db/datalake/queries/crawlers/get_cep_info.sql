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
        tplogradouro,
        logradouro,
        bairro,
        cidade,
        estado,
        replace(cep, '-', '') as cepp
    from
        datalake_raw.ebdb_cep
)
select c1.cep, c2.*
from input_ceps c1
left join ebdb_ceps c2 on c1.cep = c2.cepp
;

