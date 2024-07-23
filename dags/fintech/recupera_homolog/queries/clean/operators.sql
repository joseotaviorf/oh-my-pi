SELECT
    id_operator,
    id_operator_superior,
    id_site,
    id_operator_registration,
    id_operator_profile,
    id_dialer,
    CAST(negotiation_level AS INT) AS negotiation_level,
    operator_auth_type,
    operator_name,
    operator_code_registration_update,
    CASE
        WHEN operator_type = "F" THEN "Administrativo"
        WHEN operator_type = "1" THEN "Recebimento – Atendente"
        WHEN operator_type = "2" THEN "Recebiento – Caixa"
        WHEN operator_type = "3" THEN "Recebimento – Recepcao"
        WHEN operator_type = "A" THEN "Responsável"
        WHEN operator_type = "N" THEN "Ativo"
        WHEN operator_type = "R" THEN "Receptivo"
        WHEN operator_type = "W" THEN "Workflow"
        WHEN operator_type = "C" THEN "Cliente credor"
        WHEN operator_type = "E" THEN "Ativo Receptivo"
        WHEN operator_type = "S" THEN "Assessoria"
        WHEN operator_type = "X" THEN "Webservice"
        WHEN operator_type = "T" THEN "Executor de tarefas"
        WHEN operator_type = "I" THEN "Itinerante"
        WHEN operator_type = "L" THEN "Loja"
        WHEN operator_type = "J" THEN "Lojista"
        WHEN operator_type = "P" THEN "API"
        WHEN operator_type = "Q" THEN "API carga"
        WHEN operator_type = "K" THEN "Assesoria ativo/receptivo"
        ELSE operator_type
    END AS operator_type,
    CASE
        WHEN type_search = "T" THEN "Registro Novo"
        WHEN type_search = "A" THEN "Agenda utilizado para gravar o retorno da manager"
        WHEN type_search = "M" THEN "Não há mais registros"
        WHEN type_search = "P" THEN "Agenda programada"
        WHEN type_search = "D" THEN "Agenda automatica adiantamento"
        WHEN type_search = "C" THEN "Agenda automatica"
        WHEN type_search = "E" THEN "Estouro de registros"
        WHEN type_search = "N" THEN "Flag temporária - Não buscar nova ficha"
        ELSE type_search
    END AS type_search,
    operator_extension,
    CASE
        WHEN dialing_equipment = "D" THEN "Placa Discadora"
        WHEN dialing_equipment = "M" THEN "Manual"
        WHEN dialing_equipment = "O" THEN "Openvox preditivo"
        WHEN dialing_equipment = "W" THEN "Openvox preview"
        WHEN dialing_equipment = "V" THEN "VOScenter"
        WHEN dialing_equipment = "E" THEN "Melita"
        WHEN dialing_equipment = "C" THEN "Conector Power"
        WHEN dialing_equipment = "P" THEN "Conector Preview"
        WHEN dialing_equipment = "U" THEN "Ditronic USB"
        WHEN dialing_equipment = "L" THEN "Vocalcom"
        WHEN dialing_equipment = "G" THEN "Gennex"
        WHEN dialing_equipment = "R" THEN "Voice"
        WHEN dialing_equipment = "I" THEN "Dígitro"
        WHEN dialing_equipment = "T" THEN "Talk"
        WHEN dialing_equipment = "A" THEN "Disca URL"
        WHEN dialing_equipment = "B" THEN "OpenVox Power"
        WHEN dialing_equipment = "F" THEN "Dialtech"
        WHEN dialing_equipment = "3" THEN "Vocalcom v3"
        WHEN dialing_equipment = "J" THEN "PA Virtual"
        WHEN dialing_equipment = "K" THEN "OLOS"
        WHEN dialing_equipment = "Q" THEN "Avaya Preview"
        WHEN dialing_equipment = "2" THEN "Olos Java Script"
        WHEN NULLIF(dialing_equipment, "Nulo") IS NULL THEN "Nenhum"
        ELSE dialing_equipment
    END AS dialing_equipment,
    CASE
        WHEN operator_shift = "M" THEN "Manhã"
        WHEN operator_shift = "T" THEN "Tarde"
        WHEN operator_shift = "N" THEN "Noite"
        WHEN operator_shift = "D" THEN "Madrugada"
        ELSE operator_shift
    END AS operator_shift,
    ura_parameter,
    CASE
        WHEN monitoring_type = "T" THEN "Monitora todos"
        WHEN monitoring_type = "D" THEN "Monitora subordinado direto"
        WHEN NULLIF(monitoring_type, "Nulo") IS NULL THEN "Nenhum"
        ELSE monitoring_type
    END AS monitoring_type,
    number_dialed_external_line,
    CASE
        WHEN is_required_change_password = "S" THEN True
        ELSE False
    END AS is_required_change_password,
    CASE
        WHEN is_login_blocked = "S" THEN True
        ELSE False
    END AS is_login_blocked,
    operator_login_code,
    receipt_printer,
    is_active,
    CASE
        WHEN document_type = "0" THEN "CPF"
        WHEN document_type = "1" THEN "CNPJ"
        ELSE document_type
    END AS document_type,
    operator_document,
    CAST(records_seek AS INT) AS records_seek,
    CAST(agendas_seek AS INT) AS agendas_seek,
    CAST(records_activated AS INT) AS records_activated,
    CAST(automatic_agendas_triggered AS INT) AS automatic_agendas_triggered,
    CAST(success_calls AS INT) AS success_calls,
    CAST(attemps_login_incorrect_password AS INT) AS attemps_login_incorrect_password,
    CAST(max_tokens AS INT) AS max_tokens,
    TIMESTAMP(ts_operator_inclusion) AS ts_operator_inclusion,
    TIMESTAMP(ts_operator_registration_update) AS ts_operator_registration_update,
    TIMESTAMP(ts_password_change) AS ts_password_change,
    TIMESTAMP(ts_last_login) AS ts_last_login,
    ts_load
FROM
    datalake_recupera_homolog_raw.operators
