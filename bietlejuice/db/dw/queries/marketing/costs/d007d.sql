select distinct
        dd.sk_date::integer as sk_date,
        dr.city_group::varchar as city_group,
        (dense_rank() over (partition by dd.sk_date, dr.city_group order by fhs.sk_house_listing) +
            dense_rank() over (partition by dd.sk_date, dr.city_group order by fhs.sk_house_listing desc) - 1) /
        (dense_rank() over (partition by dd.sk_date order by fhs.sk_house_listing) +
            dense_rank() over (partition by dd.sk_date order by fhs.sk_house_listing desc) - 1)::float as share
    from dim_date dd
    join fact_house_listing_status fhs
        on dd.sk_date between fhs.sk_status_start_date and coalesce(nullif(fhs.sk_status_end_date, -1), to_char(current_date - 1, 'YYYYMMDD')::bigint)
        and fhs.status_history = 'publicado'
        and fhs.sk_status_start_date != -1
    join dim_region dr
        on dr.sk_region = fhs.sk_region
        and city_group is not null
    where dd.sk_date between 20180101 and cast(TO_CHAR(getdate() -1, 'YYYYMMDD') as integer)
        and dr.city_group not in ('Goiânia', 'Belo Horizonte')