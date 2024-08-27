SELECT
    AGAGENCY AS id_agency,
    AGFIRM AS agency_name,
    AGNICKNAME AS agency_commercial_name,
    AGIRSNUM AS cnpj,
    AGAGCYCD AS agency_type,
    AGSUPER AS super_agency,
    IF(AGSTATUS = "A", TRUE, FALSE) AS is_active_agency,
    CASE
        WHEN AGDISTTYPE = "N" THEN "Nivelada"
        WHEN AGDISTTYPE = "P" THEN "Percentual"
        ELSE AGDISTTYPE
    END AS distribution_type,
    AGADDR1 AS address,
    AGADDR2 AS neighborhood,
    AGCITY AS city,
    AGSTATE AS state,
    AGZIP AS zip_code,
    AGADDR3 AS address_complement,
    AGPHONE AS phone_number,
    AGENDOBS AS contract_termination_reason,
    IF(AGFLGCMS = 1,TRUE,FALSE) AS has_commission,
    IF(AGFLGSND = 1,TRUE,FALSE) AS has_shipments,
    AGNUMACT AS active_accounts,
    AGNUMREL AS accounts_released_month,
    AGNUMSAT AS accounts_satisfied_month,
    AGAMTCOL AS current_amount_recovered,
    AGCCRATE AS current_commission_rate,
    AGCOMLAG AS waiting_days_before_paying_commission,
    AGPCRATE AS prior_commission_fee,
    AGAMTSAT AS amount_satisfied,
    AGAMTREL AS amount_released,
    AGAMTACT AS current_active_amount,
    AGSTARTDT AS ts_start,
    AGAGNREF AS ts_assigned_agency,
    AGENDDT AS ts_contract_termination,
    NOW() AS ts_load
FROM datalake_cyber_raw.agency
