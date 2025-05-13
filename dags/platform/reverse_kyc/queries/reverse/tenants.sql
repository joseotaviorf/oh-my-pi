WITH rent_person_contracts AS (
    SELECT
        cp.cpf,
        CASE
            WHEN COUNT(DISTINCT cp.id_contract) > 1 THEN 'YES'
            ELSE 'NO'
        END AS has_another_contract
    FROM datalake_ebdb_clean.contract_person cp
    JOIN datalake_ebdb_clean.contract c ON cp.id_contract = c.id
    WHERE c.status = 'Ativo' OR c.status = 'Finalizado'
    GROUP BY cp.cpf
),
tenants AS (
    SELECT
        cp.name as name_corporate_name,
        cp.cpf as cpf_cnpj,
        CASE
            WHEN LENGTH(cp.cpf) = 14 THEN 'PF'
            WHEN LENGTH(cp.cpf) = 15 THEN 'PF'
            WHEN LENGTH(cp.cpf) = 18 THEN 'PJ'
            ELSE 'UNKNOWN'
        END AS person_type,
        cp.email,
        cp.legal_representative_name,
        cp.legal_representative_cpf,
        'TENANT' as business_relationship,
        CASE
            WHEN MAX(
                CASE
                    WHEN c.status = 'Ativo' THEN 1
                    ELSE 0
                END
            ) = 1 THEN 'ACTIVE'
            ELSE 'INACTIVE'
        END AS business_relationship_status,
        pc.has_another_contract
    FROM datalake_ebdb_clean.contract_person cp
    JOIN datalake_ebdb_clean.contract c ON c.id = cp.id_contract
    JOIN rent_person_contracts pc ON pc.cpf = cp.cpf
    WHERE
        cp.type = 'Inquilino'
        AND ((c.status = 'Ativo')
        OR (c.status = 'Finalizado' AND c.dt_termination >= CURRENT_DATE - INTERVAL '12' MONTH))
    GROUP BY
        cp.name,
        cp.cpf,
        cp.email,
        cp.legal_representative_name,
        cp.legal_representative_cpf,
        pc.has_another_contract
)
SELECT * FROM tenants