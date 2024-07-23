SELECT
    id_historical,
    id_historical_situation,
    historical_description,
    CASE
        WHEN has_complement = "S" THEN True
        ELSE False
    END AS has_complement,
    CASE
        WHEN is_exportable_occurence = "S" THEN True
        ELSE False
    END AS is_exportable_occurence,
    operator_name,
    CASE
        WHEN is_preferencial_phone_updated = "S" THEN True
        ELSE False
    END AS is_preferencial_phone_updated,
    CASE
        WHEN is_automatic_agenda = "S" THEN True
        ELSE False
    END AS is_automatic_agenda,
    CASE
        WHEN is_scheduled_agenda = "S" THEN True
        ELSE False
    END AS is_scheduled_agenda,
    CASE
        WHEN is_next_call_triggered = "S" THEN True
        ELSE False
    END AS is_next_call_triggered,
    CASE
        WHEN is_effective_contact = "S" THEN True
        ELSE False
    END AS is_effective_contact,
    CASE
        WHEN agenda_interval = "D" THEN "Dia"
        WHEN agenda_interval = "H" THEN "Hora"
        WHEN agenda_interval = "M" THEN "Minuto"
        ELSE agenda_interval
    END AS agenda_interval,
    CASE
        WHEN is_time_monitored = "S" THEN True
        ELSE False
    END AS is_time_monitored,
    CASE
        WHEN historical_type = "NO" THEN "Normal"
        WHEN historical_type = "FA" THEN "Fax"
        WHEN historical_type = "NA" THEN "Não atende"
        WHEN historical_type = "OC" THEN "Ocupado"
        WHEN historical_type = "TE" THEN "Tentativas esgotadas"
        ELSE historical_type
    END AS historical_type,
    CASE
        WHEN is_contract_linked = "S" THEN True
        ELSE False
    END AS is_contract_linked,
    CASE
        WHEN is_withdrawn_property = "S" THEN True
        ELSE False
    END AS is_withdrawn_property,
    CASE
        WHEN block_installment = "S" THEN "Bloqueia"
        WHEN block_installment = "D" THEN "Desbloqueia"
        WHEN block_installment = "N" THEN "Nenhum"
        ELSE block_installment
    END AS block_installment,
    CASE
        WHEN measure_efficiency_agreement = "E" THEN "Na emissão"
        WHEN measure_efficiency_agreement = "P" THEN "No pagamento"
        ELSE measure_efficiency_agreement
    END AS measure_efficiency_agreement,
    CASE
        WHEN measure_efficiency_receipts = "E" THEN "Na emissão"
        WHEN measure_efficiency_receipts = "P" THEN "No pagamento"
        ELSE measure_efficiency_receipts
    END AS measure_efficiency_receipts,
    CASE
        WHEN is_efficiency_measured = "S" THEN True
        ELSE False
    END AS is_efficiency_measured,
    CASE
        WHEN is_only_business_days = "S" THEN True
        ELSE False
    END AS is_only_business_days,
    CASE
        WHEN is_mandatory_phone = "S" THEN True
        ELSE False
    END AS is_mandatory_phone,
    billing_regulation,
    CASE
        WHEN is_occurence_exported = "S" THEN True
        ELSE False
    END AS is_occurence_exported,
    CASE
        WHEN is_correct_person_contacted = "S" THEN True
        ELSE False
    END AS is_correct_person_contacted,
    max_days_return_form,
    CAST(attempt_sold_out AS INT) AS attempt_sold_out,
    CAST(minutes_agenda AS INT) AS minutes_agenda,
    CAST(average_call_time AS INT) AS average_call_time,
    CAST(block_installment_days AS INT) AS block_installment_days,
    CAST(eficiency_days AS INT) AS eficiency_days,
    CAST(attempts_inactivate_phone AS INT) AS attempts_inactivate_phone,
    TIMESTAMP(ts_inclusion) AS ts_inclusion,
    TIMESTAMP(ts_last_registration) AS ts_last_registration,
    TIMESTAMP(ts_load) AS ts_load
FROM
    datalake_recupera_homolog_raw.historical
