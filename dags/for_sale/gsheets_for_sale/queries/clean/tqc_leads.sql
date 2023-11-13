SELECT
    LCASE(agent_email) as agent_email,
    IF (
        OVERLAY(OVERLAY(OVERLAY(TRANSLATE(agent_cpf,' ,.-','    ')
            PLACING '.' FROM 4)
            PLACING '.' FROM 8)
            PLACING '-' FROM 12
        ) IN ('000.000.000-00','111.111.111-11','222.222.222-22','333.333.333-33','444.444.444-44','555.555.555-55','666.666.666-66','777.777.777-77','888.888.888-88','999.999.999-99'),
        NULL,
        OVERLAY(OVERLAY(OVERLAY(TRANSLATE(agent_cpf,' ,.-','    ')
            PLACING '.' FROM 4)
            PLACING '.' FROM 8)
            PLACING '-' FROM 12
        )
    ) AS agent_cpf,
    agent_creci,
    INITCAP(lead_name) AS lead_name,
    CASE
        WHEN
            LENGTH(lead_phone) = 13
            AND SUBSTRING(lead_phone,1,3) = '+55'
            AND TRY_CAST(SUBSTRING(lead_phone,4,2) AS INT) BETWEEN 11 AND 99
            AND TRY_CAST(SUBSTRING(lead_phone,6,1) AS INT) BETWEEN 2 AND 6
            AND TRY_CAST(SUBSTRING(lead_phone,6,8) AS INT) NOT IN (22222222,33333333,44444444,55555555,66666666)
        THEN lead_phone
        WHEN
            LENGTH(lead_phone) = 14
            AND SUBSTRING(lead_phone,1,3) = '+55'
            AND TRY_CAST(SUBSTRING(lead_phone,4,2) AS INT) BETWEEN 11 AND 99
            AND TRY_CAST(SUBSTRING(lead_phone,6,1) AS INT) = 9
            AND TRY_CAST(SUBSTRING(lead_phone,7,8) AS INT) NOT IN (00000000,11111111,22222222,33333333,44444444,55555555,66666666,77777777,88888888,99999999)
        THEN lead_phone
        WHEN
            LENGTH(SUBSTRING(lead_phone,4)) NOT IN (10,11)
        THEN lead_phone
        ELSE NULL
    END AS lead_phone,
    LCASE(lead_email) AS lead_email,
    agent_visits,
    lead_interest_area,
    program_phase,
    BOOLEAN(NULLIF(is_valid_lead, '')) AS is_valid_lead,
    CAST(appointment_date AS TIMESTAMP) AS ts_appointment,
    CAST(new_lead_date AS TIMESTAMP) AS ts_new_lead
FROM
    datalake_gsheets_raw.tqc_leads
