SELECT
    id_status,
    id_operator,
    status_description,
    operator_name,
    CASE
        WHEN is_accessible = "S" THEN True
        ELSE False
    END AS is_accessible,
    CASE
        WHEN forwarding_type = "C" THEN "Distribuidor do credor"
        WHEN forwarding_type = "O" THEN "Outros"
        WHEN NULLIF(forwarding_type, "Nulo") IS NULL THEN "Nenhum operador"
        ELSE forwarding_type
    END AS forwarding_type,
    CASE
        WHEN contract_block = "D" THEN "Desbloqueio"
        WHEN contract_block = "S" THEN "Bloqueia"
        WHEN contract_block = "N" THEN "Nenhuma ação"
        ELSE contract_block
    END AS contract_block,
    CASE
        WHEN is_boleto_emission_block = "S" THEN True
        ELSE False
    END AS is_boleto_emission_block,
    CASE
        WHEN is_installment_block = "S" THEN True
        ELSE False
    END AS is_installment_block,
    CASE
        WHEN is_charge_returned = "S" THEN True
        ELSE False
    END AS is_charge_returned,
    DATE(dt_expiration) AS dt_expiration,
    TIMESTAMP(ts_status_inclusion) AS ts_status_inclusion,
    TIMESTAMP(ts_last_registration_update) AS ts_last_registration_update,
    ts_load
FROM
    datalake_recupera_homolog_raw.status
