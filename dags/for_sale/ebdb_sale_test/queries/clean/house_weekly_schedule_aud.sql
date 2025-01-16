SELECT
    id,
    imovel_id AS id_house,
    rev,
    revtype AS rev_type,
    diaDaSemana AS weekday,
    horarios_disponivel08as09 AS is_available_between_08_and_09,
    horarios_disponivel09as10 AS is_available_between_09_and_10,
    horarios_disponivel10as11 AS is_available_between_10_and_11,
    horarios_disponivel11as12 AS is_available_between_11_and_12,
    horarios_disponivel12as13 AS is_available_between_12_and_13,
    horarios_disponivel13as14 AS is_available_between_13_and_14,
    horarios_disponivel14as15 AS is_available_between_14_and_15,
    horarios_disponivel15as16 AS is_available_between_15_and_16,
    horarios_disponivel16as17 AS is_available_between_16_and_17,
    horarios_disponivel17as18 AS is_available_between_17_and_18,
    horarios_disponivel18as19 AS is_available_between_18_and_19,
    horarios_disponivel19as20 AS is_available_between_19_and_20
FROM
    datalake_ebdb_test_raw.horariosemanalimovel_aud
