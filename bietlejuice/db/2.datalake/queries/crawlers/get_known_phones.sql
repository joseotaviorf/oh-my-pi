select * from (
    select
        telefoneAnunciante as phone_number,
        nomeAnunciante as advertiser_name,
        tipo as type,
        status,
        reason,
        origem as origin,
        date(criadoEm) as created_date
    from
        ebdb.Lead
    where
        criadoEm >= date '{since}'
    union all
    select
        telefoneAnuncianteDois as phone_number,
        nomeAnunciante as advertiser_name,
        tipo as type,
        status,
        reason,
        origem as origin,
        date(criadoEm) as created_date
    from
        ebdb.Lead
    where
        criadoEm >= date '{since}'
    union all
    select
        telefoneAnuncianteTres as phone_number,
        nomeAnunciante as advertiser_name,
        tipo as type,
        status,
        reason,
        origem as origin,
        date(criadoEm) as created_date
    from
        ebdb.Lead
    where
        criadoEm >= date '{since}'
) t
where phone_number is not null and phone_number != ''