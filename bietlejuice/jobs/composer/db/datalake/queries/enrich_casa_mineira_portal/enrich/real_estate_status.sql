WITH real_estate_agency AS (
    WITH agency_created AS (
        SELECT 
            agency.id AS id_real_estate_agency,
            agency.real_estate_agency_name,
            agency.real_estate_agency_full_name,
            'CREATED' AS status,
            agency.ts_created
        FROM 
            datalake_casa_mineira_portal_clean.real_estate_agency AS agency
    ),                 
    agency_disabled AS (
        SELECT 
            agency_history.id_real_estate_agency,
            agency.real_estate_agency_name,
            agency.real_estate_agency_full_name,
            'DISABLED' AS status,
            agency_history.ts_created
        FROM
            datalake_casa_mineira_portal_clean.real_estate_agency_history AS agency_history
        INNER JOIN 
            datalake_casa_mineira_portal_clean.real_estate_agency AS agency
                ON agency.id = agency_history.id_real_estate_agency
        WHERE 
            agency_history.modified_column = 'desativado_em'
            AND agency_history.modified_value IS NOT NULL
    ),               
    agency_reactivated AS (
        SELECT 
            agency_history.id_real_estate_agency,
            agency.real_estate_agency_name,
            agency.real_estate_agency_full_name,
            'REACTIVATED' AS status,
            agency_history.ts_created
        FROM
            datalake_casa_mineira_portal_clean.real_estate_agency_history AS agency_history
        INNER JOIN 
            datalake_casa_mineira_portal_clean.real_estate_agency AS agency
                ON agency.id = agency_history.id_real_estate_agency
        WHERE 
            agency_history.modified_column = 'desativado_em'
            AND agency_history.modified_value IS NULL
    )
    SELECT *
    FROM
        agency_created
    UNION ALL
    SELECT *
    FROM
        agency_disabled
    UNION
    SELECT *
    FROM 
        agency_reactivated
)
SELECT 
    id_real_estate_agency,
    real_estate_agency_name,
    real_estate_agency_full_name,
    status,
    ts_created,
    LEAD (ts_created)
        OVER (
        PARTITION BY id_real_estate_agency
        ORDER BY ts_created) AS ts_status_ended
FROM 
    real_estate_agency
