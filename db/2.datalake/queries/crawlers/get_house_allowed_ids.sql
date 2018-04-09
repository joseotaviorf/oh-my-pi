select
    r.id as id
from
    datalake_raw.ebdb_regiao r
join
    datalake_raw.ebdb_regiao m
    on m.id = r.regiaopai_id
join
    datalake_raw.ebdb_regiao c
    on c.id = m.regiaopai_id
where
    r.nivel = 'SubRegiao'
    and(
        c.nome in(
            'São Bernardo do Campo',
            'São Caetano do Sul',
            'Santo André',
            'Barueri',
            'Campinas',
            'Osasco'
        )
        or(
            c.nome = 'São Paulo'
            and r.nome in(
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
    )