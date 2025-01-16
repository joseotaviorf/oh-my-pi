SELECT
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    diaDaSemana as weekday,
    horarios_disponivel08as09 as is_available_between_08_and_09,
    horarios_disponivel09as10 as is_available_between_09_and_10,
    horarios_disponivel10as11 as is_available_between_10_and_11,
    horarios_disponivel11as12 as is_available_between_11_and_12,
    horarios_disponivel12as13 as is_available_between_12_and_13,
    horarios_disponivel13as14 as is_available_between_13_and_14,
    horarios_disponivel14as15 as is_available_between_14_and_15,
    horarios_disponivel15as16 as is_available_between_15_and_16,
    horarios_disponivel16as17 as is_available_between_16_and_17,
    horarios_disponivel17as18 as is_available_between_17_and_18,
    horarios_disponivel18as19 as is_available_between_18_and_19,
    horarios_disponivel19as20 as is_available_between_19_and_20,
    imovel_id as id_house
FROM
    datalake_ebdb_test_raw.horariosemanalimovel
