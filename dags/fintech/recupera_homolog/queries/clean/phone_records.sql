SELECT
    id_creditor,
    id_customer,
    phone_number,
    phone_type,
    branch_line,
    CASE
        WHEN is_phone_preferential = "P" THEN "Preferencial"
        WHEN NULLIF(is_phone_preferential, "Nulo") IS NULL THEN "Normal"
        ELSE is_phone_preferential
    END AS is_phone_preferential,
    CASE
        WHEN is_inactive_phone = "S" THEN True
        ELSE False
    END AS is_inactive_phone,
    CASE
        WHEN phone_modality = "0" THEN "Nenhum"
        WHEN phone_modality = "1" THEN "Celular"
        WHEN phone_modality = "2" THEN "Fixo"
        ELSE phone_modality
    END AS phone_modality,
    country_code,
    phone_operator_code,
    ddd_code,
    dismembered_phone,
    CASE
        WHEN origin_update_phone = "0" THEN "Nenhum"
        WHEN origin_update_phone = "1" THEN "Manual"
        WHEN origin_update_phone = "2" THEN "Sistema"
        WHEN origin_update_phone = "3" THEN "Enriquecimento"
        WHEN origin_update_phone = "4" THEN "WebService"
        ELSE origin_update_phone
    END AS origin_update_phone,
    origin_update_phone_description,
    customer_name,
    TIMESTAMP(ts_phone_update) AS ts_phone_update,
    ts_load
FROM
    datalake_recupera_homolog_raw.phone_records
