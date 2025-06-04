WITH
  deduplicate_agency_group AS (
  SELECT
    agency_group,
    id_agency
  FROM datalake_cyber_clean.agency_group
  QUALIFY ROW_NUMBER() OVER(PARTITION BY agency_group ORDER BY percentage_remuneration DESC) = 1
),
get_agency_details AS (
  SELECT
    a.id_agency,
    COALESCE(aa.agency_name, a.agency_name) AS agency_name,
    COALESCE(aa.agency_type, a.agency_type) AS agency_type,
    COALESCE(aa.ts_start, a.ts_start) AS ts_start
  FROM datalake_cyber_clean.agency AS a
  LEFT JOIN deduplicate_agency_group AS ag
    ON a.id_agency = ag.agency_group
  LEFT JOIN datalake_cyber_clean.agency AS aa
    ON ag.id_agency = aa.id_agency
)
SELECT DISTINCT
    UPPER(COALESCE(u.id_user, agg.id_agency)) AS id_user,
    COALESCE(u.id_agency, agg.id_agency) AS id_agency,
    UPPER(COALESCE(u.user_name, agg.agency_name)) AS user_name,
    LOWER(u.user_email) AS user_email,
    u.user_type,
    u.department AS user_department,
    COALESCE(ag.agency_type, agg.agency_type) AS agency_type,
    COALESCE(ag.agency_name, agg.agency_name) AS agency_name,
    CASE
        WHEN UPPER(u.user_email) LIKE "%ATENTO%" THEN "ATENTO"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "PASCH%" THEN "PASCHOALOTTO"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "%TRC%" THEN "TRC"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "%GRB%" THEN "GRB"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "%MEETC%" THEN "MEETCALL"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "%MONES%" THEN "MONEST"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "%PORTAL%" THEN "PORTAL_QUINTOANDAR"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) = "WEBHELP" THEN "WEBHELP"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "%WHELP%" THEN "WEBHELP"
        WHEN UPPER(COALESCE(ag.agency_name, agg.agency_name, u.id_user)) LIKE "%WEBHELP%" THEN "WEBHELP"
        WHEN UPPER(COALESCE(u.id_user, agg.agency_name)) LIKE "%SERASA%" THEN "SERASA"
        WHEN UPPER(COALESCE(u.id_user, agg.agency_name)) = "QUINTO" THEN "COBRANÇA_INTERNA_QA"
        WHEN UPPER(COALESCE(u.id_user, agg.agency_name)) LIKE "TOPPEN%" THEN "TOPPEN"
        ELSE UPPER(COALESCE(ag.agency_name, agg.agency_name))
    END AS company_name,
    COALESCE(u.ts_user_created, agg.ts_start) AS ts_user_created
FROM datalake_cyber_clean.users AS u
LEFT JOIN get_agency_details AS ag
  ON u.id_agency = ag.id_agency
FULL OUTER JOIN get_agency_details AS agg
  ON UPPER(u.id_user) = UPPER(agg.id_agency)
