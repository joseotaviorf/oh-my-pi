WITH
current_people AS (
    SELECT 
        id_person, 
        person_number
    FROM 
        datalake_pin_core_clean.all_people
    WHERE 
        dt_effective_ended >= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_effective_ended DESC) = 1
),
current_assignments AS (
    SELECT 
        id_assignment, 
        id_period_of_service, 
        id_person, 
        assignment_number, 
        assignment_type
    FROM 
        datalake_pin_core_clean.all_assignments
    WHERE
        assignment_type IN ('E', 'C', 'P')
        AND dt_effective_ended >= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_assignment ORDER BY dt_effective_ended DESC) = 1
),
current_names AS (
    SELECT 
        id_person, 
        full_name,
        first_name,
        last_name
    FROM 
        datalake_pin_core_clean.person_name
    WHERE
        name_type = 'GLOBAL'
        AND dt_effective_ended >= DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_effective_ended DESC) = 1
),
work_emails AS (
    SELECT 
        id_person, 
        email_address
    FROM 
        datalake_pin_core_clean.email_address
    WHERE
        email_type = 'W1'
        AND (dt_ended >= DATE('{load_end_date}') OR dt_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_ended DESC) = 1
),
personal_emails AS (
    SELECT 
        id_person, 
        email_address
    FROM 
        datalake_pin_core_clean.email_address
    WHERE
        email_type = 'H1'
        AND (dt_ended >= DATE('{load_end_date}') OR dt_ended IS NULL)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_ended DESC) = 1
),
test_users AS (
    SELECT 
        id_person
    FROM 
        datalake_pin_core_clean.external_application_identifier
    WHERE
        type_external_identifier = 'ID_ONDA1'
        AND dt_ended IS NULL
)

SELECT
    a.id_assignment,
    a.id_period_of_service,
    a.id_person,
    COALESCE(wr.registration, lr.legacy_registration) AS legacy_registration,
    a.assignment_number,
    a.assignment_type,
    p.person_number,
    n.first_name,
    n.last_name,
    n.full_name,
    LOWER(we.email_address) AS work_email,
    LOWER(pe.email_address) AS personal_email,
    tu.id_person IS NOT NULL AS is_user_test,
    NOW() AS ts_load
FROM
    current_people AS p
INNER JOIN 
    current_assignments AS a 
        ON p.id_person = a.id_person
INNER JOIN 
    current_names AS n 
        ON p.id_person = n.id_person
LEFT JOIN 
    work_emails AS we 
        ON p.id_person = we.id_person
LEFT JOIN 
    personal_emails AS pe 
        ON p.id_person = pe.id_person
LEFT JOIN 
    test_users AS tu 
        ON p.id_person = tu.id_person
LEFT JOIN 
    datalake_hr_system_custom_clean.workers_registration AS wr 
        ON a.assignment_number = wr.assignment_number
LEFT JOIN 
    datalake_gsheets_people_clean.legacy_registration AS lr 
        ON LOWER(lr.work_email) = LOWER(we.email_address)