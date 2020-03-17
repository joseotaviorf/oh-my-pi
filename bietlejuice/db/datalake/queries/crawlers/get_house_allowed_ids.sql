select
    r.id_region as id
from
    datalake_ebdb_clean_prod.region r
join
    datalake_ebdb_clean_prod.region m
    on m.id_region = r.id_parent_region
join
    datalake_ebdb_clean_prod.region c
    on c.id_region = m.id_parent_region
where
    r.level = 'SubRegiao'
    and(
        c.name in(
            'São Bernardo do Campo',
            'São Caetano do Sul',
            'Santo André',
            'Barueri',
            'Campinas',
            'Osasco'
        )
        or(
            c.name = 'São Paulo'
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
            c.name = 'Belo Horizonte'
        )
    )