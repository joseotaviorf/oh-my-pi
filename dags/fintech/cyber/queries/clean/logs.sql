SELECT
    ACACCT AS id_contract,
    ACCIDNAM AS id_user,
    CASE
        WHEN ACACCTG = "1" THEN "QuintoAndar"
        WHEN ACACCTG = "2" THEN "QuintoCred"
        ELSE ACACCTG
    END AS contract_group,
    ACLCCODE AS letter_code,
    ACARCOD AS region_code,
    CASE
        WHEN ACACCODE = "AP" THEN "App"
        WHEN ACACCODE = "AV" THEN "Agente virtual"
        WHEN ACACCODE = "CT" THEN "Carta Correios"
        WHEN ACACCODE = "B" THEN "Carta Boleto"
        WHEN ACACCODE = "CC" THEN "Carta Cartório"
        WHEN ACACCODE = "DI" THEN "Discador"
        WHEN ACACCODE = "DM" THEN "Discador Manual"
        WHEN ACACCODE = "EB" THEN "Email Boleto"
        WHEN ACACCODE = "EC" THEN "Email Boleto Carta Cartório"
        WHEN ACACCODE = "EM" THEN "Email"
        WHEN ACACCODE = "HS" THEN "HSM"
        WHEN ACACCODE = "PE" THEN "Pesquisa"
        WHEN ACACCODE = "PO" THEN "Portal"
        WHEN ACACCODE = "RC" THEN "RCS"
        WHEN ACACCODE = "SE" THEN "Serasa"
        WHEN ACACCODE = "SM" THEN "SMS"
        WHEN ACACCODE = "UR" THEN "URA"
        WHEN ACACCODE = "WH" THEN "Whatsapp"
        WHEN ACACCODE = "WM" THEN "Whatsapp Manual"
        ELSE ACACCODE
    END AS action,
    CASE
        WHEN ACRCCODE = "AA" THEN "Acordo"
        WHEN ACRCCODE = "BB" THEN "Localizado"
        WHEN ACRCCODE = "CC" THEN "Não Localizado"
        WHEN ACRCCODE = "DD" THEN "Ligação Sem Sucesso"
        WHEN ACRCCODE = "EE" THEN "Indicio de Fraude"
        WHEN ACRCCODE = "FF" THEN "Atualização Cadastral"
        WHEN ACRCCODE = "GG" THEN "Falecido"
        WHEN ACRCCODE = "II" THEN "Carta Devolvida"
        WHEN ACRCCODE = "JJ" THEN "Alega Pagamento Imobiliaria"
        WHEN ACRCCODE = "KK" THEN "Alega Pagamento"
        WHEN ACRCCODE = "LL" THEN "Preventivo - Localizado"
        WHEN ACRCCODE = "MM" THEN "Preventivo - Não Localizado"
        WHEN ACRCCODE = "NN" THEN "Enviado"
        WHEN ACRCCODE = "ZZ" THEN "Outros"
        ELSE ACRCCODE
    END AS result,
    ACSEQNUM AS sequence_number,
    ACCOMM AS comment,
    ACPHONE AS phone_number,
    ACEXT AS phone_extension,
    ACLAT AS latitude,
    ACLNG AS longitude,
    ACACTDTE AS ts_activity,
    ACENTDTE AS ts_load_cyber,
    NOW() AS ts_load
FROM datalake_cyber_raw.actfil
