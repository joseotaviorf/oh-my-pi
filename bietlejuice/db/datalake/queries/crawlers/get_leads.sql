-- query to get crawled leads
-- params: started_on, ws, started_on, ws, states

with good_phones as(
    select
        phone,
        count( distinct id ) n_listings
    from
        datalake_raw.crawlers
    cross join
        unnest(
            regexp_extract_all(
                phones,
                '\d+'
            )
        ) as t(phone)
    where
        started_on = date '{started_on}'
        and ws = '{ws}'
    group by
        phone
    having
        count( distinct id ) <= 5
)
select distinct
    c.id,
    c.type,
    c.rent,
    c.advertiser_name,
    c.phones,
    c.street,
    c.neighborhood,
    c.iptu,
    c.condominium,
    c.bedrooms,
    c.toilets,
    c.useful_area,
    c.neighborhood,
    c.city,
    c.state,
    c.cep,
    c.lat,
    c.lng,
    date(
        if(
            updated_on != '',
            substr(
                updated_on,
                1,
                10
            )
        )
    ) updated_on,
    c.url,
from
    datalake_raw.crawlers c
cross join
    unnest(
        regexp_extract_all(
            phones,
            '\d+'
        )
    ) as t(phone)
join
    good_phones gp
    on gp.phone = t.phone
where
    started_on = date '{started_on}'
    and ws = '{ws}'
    and date(
        if(
            updated_on != '',
            substr(
                updated_on,
                1,
                10
            )
        )
    )>= date '{since}'
    and (advertiser_type != 'b2c' or advertiser_type is null)
    and lower(state) in ('{states}')
;