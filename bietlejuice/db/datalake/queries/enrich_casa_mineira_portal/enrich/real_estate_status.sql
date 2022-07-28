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
),
real_estate_status AS (
    SELECT *,
    LEAD (ts_created) 
    OVER (
        PARTITION BY 
            id_real_estate_agency
        ORDER BY 
            ts_created
    ) AS ts_status_ended
FROM 
    real_estate_agency
)

/*
    ts_created and ts_status_ended are the timestamps in which the status changes in the system, however
    they aren't really the dates in which the changes are actually applied for billing and budget. Those
    are actually dt_consider_status_started and dt_consider_status_ended.

    If an agency changes status until the 15th, dt_consider_status_started will be the current month. However
    after the 15th, it will be the next month. 
    As for dt_consider_status_ended: if the status ends until the 15th, it will be the previous month. Otherwise,
    it will be the current month.
*/
SELECT
    id_real_estate_agency,
    real_estate_agency_name,
    real_estate_agency_full_name,
    status,
    CASE 
        WHEN EXTRACT(day FROM ts_created) > 15 THEN ADD_MONTHS(DATE_TRUNC('month', ts_created), 1)
        ELSE DATE_TRUNC('month', ts_created)
    END AS dt_consider_status_started,
    CASE
        WHEN EXTRACT(day FROM ts_status_ended) > 15 THEN DATE_TRUNC('month', ts_status_ended)
        ELSE ADD_MONTHS(DATE_TRUNC('month', ts_status_ended), -1)
    END AS dt_consider_status_ended,
    ts_created,
    ts_status_ended
FROM 
    real_estate_status