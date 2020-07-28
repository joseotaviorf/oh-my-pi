select
    r.id
from
    datalake_ebdb_region_prod.region r
where
    r.level = 'SubRegiao'
    and(
        r.city_name in(
            'São Bernardo do Campo',
            'São Caetano do Sul',
            'Santo André',
            'Barueri',
            'Campinas',
            'Osasco'
        )
        or(
            r.city_name = 'São Paulo'
            and r.name in(
                'Vila Mariana',
                'Ipiranga',
                'Cambuci',
                'Aclimação',
                'Liberdade',
                'Bosque da Saúde',
                'Pinheiros',
                'Vila Madalena',
                'Alto de Pinheiros',
                'Sumaré',
                'Pacaembu',
                'Água Branca',
                'Casa Verde',
                'Santana',
                'Jardim São Paulo'
            )
        )
        or(
            r.city_name = 'Belo Horizonte'
        )
    )