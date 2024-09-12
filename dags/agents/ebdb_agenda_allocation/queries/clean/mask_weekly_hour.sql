SELECT 
    id,
    workcontract_id AS id_work_contract,
    diadasemana AS day_of_week,
    horarios_disponivel08as09 AS has_hours_between_08_and_09_available,
    horarios_disponivel09as10 AS has_hours_between_09_and_10_available,
    horarios_disponivel10as11 AS has_hours_between_10_and_11_available,
    horarios_disponivel11as12 AS has_hours_between_11_and_12_available,
    horarios_disponivel12as13 AS has_hours_between_12_and_13_available,
    horarios_disponivel13as14 AS has_hours_between_13_and_14_available,
    horarios_disponivel14as15 AS has_hours_between_14_and_15_available,
    horarios_disponivel15as16 AS has_hours_between_15_and_16_available,
    horarios_disponivel16as17 AS has_hours_between_16_and_17_available,
    horarios_disponivel17as18 AS has_hours_between_17_and_18_available,
    horarios_disponivel18as19 AS has_hours_between_18_and_19_available,
    horarios_disponivel19as20 AS has_hours_between_19_and_20_available,
    criadoem AS ts_created,
    atualizadoem AS ts_updated
FROM
    datalake_ebdb_test_raw.horariosemanalmascara