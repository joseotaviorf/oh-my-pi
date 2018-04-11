select
    telefoneanunciante as phone_number,
    nomeanunciante as advertiser_name,
    tipo as type,
    status,
    reason,
    origem as origin,
    date(if(criadoem != '', substr(criadoem, 1, 10))) as created_date
from
    datalake_raw.ebdb_lead
where
    regexp_extract(telefoneanunciante, '(\+\d\d)?(\d+)', 2) in ('{phone_list}')
    and date(if(criadoem != '', substr(criadoem, 1, 10))) >= date '{since}'
union all
select
    telefoneanunciantedois as phone_number,
    nomeanunciante as advertiser_name,
    tipo as type,
    status,
    reason,
    origem as origin,
    date(if(criadoem != '', substr(criadoem, 1, 10))) as created_date
from
    datalake_raw.ebdb_lead
where
    regexp_extract(telefoneanunciantedois, '(\+\d\d)?(\d+)', 2) in ('{phone_list}')
    and date(if(criadoem != '', substr(criadoem, 1, 10))) >= date '{since}'
union all
select
    telefoneanunciantetres as phone_number,
    nomeanunciante as advertiser_name,
    tipo as type,
    status,
    reason,
    origem as origin,
    date(if(criadoem != '', substr(criadoem, 1, 10))) as created_date
from
    datalake_raw.ebdb_lead
where
    regexp_extract(telefoneanunciantetres, '(\+\d\d)?(\d+)', 2) in ('{phone_list}')
    and date(if(criadoem != '', substr(criadoem, 1, 10))) >= date '{since}'
