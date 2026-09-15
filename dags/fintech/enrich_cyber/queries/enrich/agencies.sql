WITH
agency AS (
    SELECT
        id_agency,
        CASE
            WHEN UPPER(agency_name) LIKE 'PASCH%' THEN 'PASCHOALOTTO'
            WHEN UPPER(agency_name) LIKE '%LLC%' THEN 'LLC'
            WHEN UPPER(agency_name) LIKE '%PLC%' THEN 'LLC'
            ELSE UPPER(agency_name)
        END AS agency_name,
        agency_type,
        ts_start
    FROM datalake_cyber_clean.agency
),
agency_group_base AS (
    SELECT
        UPPER(ag.agency_group) AS id_agency_group,
        UPPER(ag.id_agency) AS id_agency,
        a.agency_name,
        UPPER(a.agency_type) AS agency_type,
        FIRST_VALUE(IF(UPPER(a.agency_type) = 'ASSESSORIA JURÍDICA', a.agency_name, NULL), TRUE) OVER(PARTITION BY ag.agency_group ORDER BY ag.percentage_remuneration DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS juridical_agency,
        FIRST_VALUE(IF(UPPER(a.agency_type) = 'ASSESSORIA CONVENCIONAL', a.agency_name, NULL), TRUE) OVER(PARTITION BY ag.agency_group ORDER BY ag.percentage_remuneration DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS conventional_agency,
        FIRST_VALUE(ag.id_agency) OVER(PARTITION BY ag.agency_group ORDER BY ag.percentage_remuneration DESC) AS id_main_agency,
        FIRST_VALUE(a.agency_name) OVER(PARTITION BY ag.agency_group ORDER BY ag.percentage_remuneration DESC) AS main_agency_name,
        FIRST_VALUE(UPPER(a.agency_type)) OVER(PARTITION BY ag.agency_group ORDER BY ag.percentage_remuneration DESC) AS main_agency_type,
        FIRST_VALUE(UPPER(a.ts_start)) OVER(PARTITION BY ag.agency_group ORDER BY ag.percentage_remuneration DESC) AS ts_main_agency_start
    FROM datalake_cyber_clean.agency_group AS ag
    LEFT JOIN agency AS a
        ON ag.id_agency = a.id_agency
),
get_agency_group_details AS (
    SELECT
        id_agency_group,
        id_main_agency,
        juridical_agency AS juridical_agency,
        conventional_agency AS conventional_agency,
        SORT_ARRAY(COLLECT_SET(id_agency)) AS id_agencies_group,
        main_agency_name,
        main_agency_type,
        SORT_ARRAY(COLLECT_SET(agency_name)) AS agencies_name_group,
        ts_main_agency_start
    FROM agency_group_base
    GROUP BY
        id_agency_group,
        id_main_agency,
        juridical_agency,
        conventional_agency,
        main_agency_name,
        main_agency_type,
        ts_main_agency_start
)
SELECT
    COALESCE(ag.id_agency_group, UPPER(a.id_agency)) AS id_agency,
    COALESCE(ag.id_main_agency, UPPER(a.id_agency)) AS id_main_agency,
    ag.juridical_agency,
    ag.conventional_agency,
    ag.id_agencies_group,
    COALESCE(ag.main_agency_name, a.agency_name) AS main_agency_name,
    COALESCE(ag.main_agency_type, UPPER(a.agency_type)) AS main_agency_type,
    ag.agencies_name_group,
    COALESCE(ag.ts_main_agency_start, a.ts_start) AS ts_start
FROM
    agency AS a
FULL OUTER JOIN
    get_agency_group_details AS ag
        ON a.id_agency = ag.id_agency_group
