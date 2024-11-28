SELECT
    AVCODE AS code,
    CASE
        WHEN AVTYPE =  "A" THEN "Ação"
        WHEN AVTYPE =  "R" THEN "Resultado"
        WHEN AVTYPE =  "L" THEN "Carta"
        WHEN AVTYPE =  "F" THEN "Função"
        WHEN AVTYPE =  "S" THEN "Busca de contas"
        WHEN AVTYPE =  "W" THEN "Tela"
        ELSE AVTYPE
    END AS code_type,
    CASE
        WHEN AVCLTYPE = 0 THEN "Todos"
        WHEN AVCLTYPE = 1 THEN "Auxiliar"
        WHEN AVCLTYPE = 2 THEN "Gestor"
        WHEN AVCLTYPE = 3 THEN "Supervisor"
        WHEN AVCLTYPE = 10 THEN "Todos (de Legal)"
        WHEN AVCLTYPE = 11 THEN "Auxiliar Legal"
        WHEN AVCLTYPE = 12 THEN "Advogado"
        WHEN AVCLTYPE = 13 THEN "Advogado supervisor"
        ELSE AVCLTYPE
    END AS code_available_manager,
    CASE
        WHEN AVCUTYPE = 0 THEN "Disponível para todos os usuários"
        WHEN AVCUTYPE = 1 THEN "Disponível para os usuários internos"
        WHEN AVCUTYPE = 2 THEN "Disponível para usuários externos"
        ELSE AVCUTYPE
    END AS user_type,
    AVCLASS AS result_code_class,
    IF(AVCNTFLG = 1, TRUE, FALSE) AS is_valid_contact,
    IF(AVCOMFLG = 1, TRUE, FALSE) AS must_add_comment,
    CASE
        WHEN AVLTRFLG = "0" THEN "Opcional"
        WHEN AVLTRFLG = "1" THEN "Sim"
        WHEN AVLTRFLG = "2" THEN "Não"
        ELSE AVLTRFLG
    END AS requires_letter,
    AVDAYS AS days_to_next_contact,
    AVWEIGHT AS activity_score,
    AVCOST AS cost,
    AVDESC AS code_description,
    CASE
        WHEN UPPER(AVACCTG) = "*" THEN "Geral"
        WHEN UPPER(AVACCTG) = "N" THEN "Grupo específico"
        WHEN UPPER(AVACCTG) = "J" THEN "Para legal"
        ELSE AVACCTG
    END AS group,
    AVTELRANK AS phone_number_rank,
    CASE
        WHEN UPPER(AVMODULE) = "L" THEN "CyberLegal"
        WHEN UPPER(AVMODULE) = "N" THEN "Todos os demais"
        ELSE AVMODULE
    END AS module,
    AVINACCT,
    AVRESULT,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_raw.actvertb
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
QUALIFY ROW_NUMBER() OVER(PARTITION BY AVCODE, AVTYPE, AVACCTG ORDER BY MAKE_DATE(year,month,day) DESC) = 1
