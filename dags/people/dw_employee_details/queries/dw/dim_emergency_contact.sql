WITH
employees AS (
    SELECT DISTINCT
        im.id_person,
        im.person_number,
        im.assignment_number,
        im.dt_started AS dt_assignment_started,
        im.dt_actual_termination AS dt_assignment_ended
    FROM
        datalake_people.identifier_mapping AS im
    WHERE
        im.is_user_test = FALSE
        AND im.assignment_type IN ('C', 'E')
),
emergency_contacts AS (
    SELECT
        pei.id_person,
        pei.id_person_extra_info,
        INITCAP(
            TRIM(
                REGEXP_REPLACE(
                    TRANSLATE(
                        REGEXP_REPLACE(REGEXP_REPLACE(pei.id_meeting, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '),
                        'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ',
                        'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
                    ),
                    ' +', ' '
                )
            )
        ) AS contact_name,
        COALESCE(flv.meaning, pei.contact_relationship) AS contact_relationship,
        TRIM(REGEXP_REPLACE(pei.id_rating_impact, '^[A-Za-z][A-Za-z][A-Za-z]? ', '')) AS phone_country_code,
        pei.id_rating_behavior AS phone_area_code,
        pei.id_rating_leadership AS phone_number,
        pei.dt_effective_started,
        NULLIF(pei.dt_effective_ended, DATE '4712-12-31') AS dt_effective_ended_normalized,
        ROW_NUMBER() OVER (
            PARTITION BY pei.id_person
            ORDER BY pei.id_person_extra_info
        ) AS contact_priority
    FROM
        datalake_pin_core_clean.people_extra_info AS pei
    LEFT JOIN
        datalake_pin_core_clean.foundation_lookup_value AS flv
        ON flv.lookup_code = pei.contact_relationship
        AND flv.lookup_type = 'QA_CONTATO_EMERGENCIA'
        AND flv.language = 'US'
    WHERE
        pei.information_type = 'Contatos de Emergência'
)
SELECT
    MD5(
        CONCAT_WS(
            '|',
            CAST(emp.id_person AS STRING),
            CAST(ec.contact_priority AS STRING),
            CAST(ec.dt_effective_started AS STRING)
        )
    ) AS sk_emergency_contact_version,
    emp.person_number,
    ec.contact_name,
    ec.contact_relationship,
    ec.phone_country_code,
    ec.phone_area_code,
    ec.phone_number,
    CONCAT_WS(' ', ec.phone_country_code, ec.phone_area_code, ec.phone_number) AS full_phone_number,
    ec.dt_effective_started AS dt_valid_from,
    COALESCE(ec.dt_effective_ended_normalized, DATE '9999-12-31') AS dt_valid_to,
    (
        ec.dt_effective_ended_normalized IS NULL
        OR ec.dt_effective_ended_normalized > CURRENT_DATE()
    ) AS is_current,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    employees AS emp
INNER JOIN
    emergency_contacts AS ec
        ON emp.id_person = ec.id_person
        AND COALESCE(emp.dt_assignment_ended, DATE '9999-12-31') >= ec.dt_effective_started
        AND COALESCE(ec.dt_effective_ended_normalized, DATE '9999-12-31') >= emp.dt_assignment_started
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            emp.id_person,
            ec.contact_priority,
            ec.dt_effective_started
        ORDER BY
            emp.dt_assignment_started DESC
    ) = 1
