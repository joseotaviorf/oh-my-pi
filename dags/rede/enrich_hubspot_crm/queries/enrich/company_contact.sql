WITH exploded_contact_associations AS (
    SELECT
        id_contact,
        occupation,
        EXPLODE(company_associations) AS company,
        ts_created AS ts_contact_created
    FROM
        datalake_hubspot.contact
),
company_contacts AS (
    SELECT
        id_contact,
        company.id AS id_company,
        CASE company.type
            WHEN 'contact_to_company' THEN 'MAIN_COMPANY'
            ELSE 'SECONDARY_COMPANY'
        END AS company_association_type,
        occupation,
        ts_contact_created
    FROM
        exploded_contact_associations
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_contact,
                id_company
            ORDER BY
                company_association_type -- Main comes before secondary alphabetically. If the company is both main and secondary, keep only the primary record
        ) = 1
)
SELECT
    id_company,
    id_contact,
    company_association_type,
        CASE
            WHEN occupation IN ('Dono/CEO', 'Sócio/Diretor', 'Gerente') AND ROW_NUMBER() OVER (
                PARTITION BY
                    id_company
                ORDER BY
                    occupation = 'Dono/CEO' DESC,
                    occupation = 'Sócio/Diretor' DESC,
                    occupation = 'Gerente' DESC,
                    ts_contact_created
            ) = 1 THEN 'DECIDING_CONTACT'
            ELSE 'NON_DECIDING_CONTACT'
        END AS contact_association_type,
    occupation
FROM
    company_contacts