with exclusives as (
    select distinct
        i.id,
        cast(i.aluguel as double) as rent,
        cast(i.lat as double) as lat,
        cast(i.lng as double) as lng,
        cast(i.condominio as double) as condo,
        cast(i.areatotal as bigint) as area,
        cast(i.numeroQuartos as smallint) as bedrooms,
        cast(if(i.firstpublication <> '', i.firstpublication) as timestamp) as firstpublication,
        u.nome name,
        u.telefonePrincipal as phone_number,
        u.email as email
    from datalake_raw.ebdb_imovel i
    join datalake_raw.ebdb_usuario u on u.id = i.usuario_id
    join datalake_raw.ebdb_specialcondition sc
        on sc.imovel_id = i.id
    where (sc.optedOutAt is null or sc.optedOutat = '')
        and i.status = 'publicado'
),
crawled as (
    select distinct
        url,
        advertiser_name,
        cast(lat as double) as lat,
        cast(lng as double) as lng,
        cast(if(rent <> '', rent) as double) as rent,
        cast(if(condominium <> '', condominium) as double) as condo,
        cast(if(iptu <> '', iptu) as double) as iptu,
        cast(if(useful_area <> '', useful_area) as bigint) as area,
        cast(if(bedrooms <> '', bedrooms) as smallint) as bedrooms,
        cast(if(updated_on <> '', updated_on) as date) as updated_on
    from datalake_raw.crawlers
    where ((ws = 'vivareal' and started_on = (select max(started_on) from datalake_raw.crawlers where ws='vivareal'))
            or (ws = 'zapimoveis' and started_on = (select max(started_on) from datalake_raw.crawlers where ws='zapimoveis')))
        and not regexp_like(advertiser_name, '(?i)quinto ?andar')
        and lat is not null and lat <> '0'
        and lng is not null and lng <> '0'
)
select distinct
    ex.id,
    c.url,
    c.advertiser_name as anunciante,
    ex.firstpublication as publicacao_5a_em,
    c.updated_on atualizacao_externa_em,
    ex.name as pp_nome,
    ex.phone_number as pp_telefone,
    ex.email as pp_email
from exclusives ex
join crawled c
    on (acos(sin(radians(ex.lat)) * sin(radians(c.lat)) + cos(radians(ex.lat)) * cos(radians(c.lat)) * cos(radians(ex.lng) - radians(c.lng))) * 6371000 <= {distance_m})
where (abs(ex.condo - c.condo) <= ex.condo*{condo_percent} or c.condo is null)
    and (abs(ex.rent - c.rent) <= ex.rent*{rent_percent} or c.rent is null)
    and (abs(ex.area - c.area) <= ex.area*{area_percent} or c.area is null)
    and (ex.bedrooms = c.bedrooms or c.bedrooms is null)