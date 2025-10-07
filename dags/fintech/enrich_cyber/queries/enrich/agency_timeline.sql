SELECT
    id_contract,
    id_agency,
    main_agency_name,
    EXPLODE(
        SEQUENCE(
            dt_start_interval,
            GREATEST(dt_start_interval, IF(dt_end_interval = LAST_DAY(CURRENT_DATE), CURRENT_DATE, dt_end_interval))
        )
    ) AS dt_reference
FROM
    datalake_cyber.contract_agency_distribution
WHERE
    creditor = 'QuintoAndar'
    AND dt_end_interval IS NOT NULL
    AND dt_start_interval <= dt_end_interval
