WITH record_selection AS (
    SELECT
        id,
        key AS id_issue,
        GET_JSON_OBJECT(fields,'$.customfield_10200.requestType.name') AS request_type,
        GET_JSON_OBJECT(fields,'$.summary') AS summary,
        GET_JSON_OBJECT(fields,'$.description') AS issue_description,
        GET_JSON_OBJECT(fields,'$.issuetype.name') AS category,
        GET_JSON_OBJECT(fields,'$.status.name') AS current_status,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.statuscategorychangedate'), '-0300', '') AS TIMESTAMP) AS ts_status_category_changed,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.created'), '-0300', '') AS TIMESTAMP) AS ts_created,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.resolutiondate'), '-0300', '') AS TIMESTAMP) AS ts_resolved,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.updated'), '-0300', '') AS TIMESTAMP) AS ts_updated,
        GET_JSON_OBJECT(fields,'$.reporter.displayName') AS reporter_name,
        GET_JSON_OBJECT(fields,'$.reporter.emailAddress') AS reporter_email,
        GET_JSON_OBJECT(fields,'$.creator.displayName') AS creator_name,
        GET_JSON_OBJECT(fields,'$.creator.emailAddress') AS creator_email,
        GET_JSON_OBJECT(fields,'$.customfield_10563.value') AS departament,
        GET_JSON_OBJECT(fields,'$.customfield_10564.value') AS service_location,
        GET_JSON_OBJECT(fields,'$.assignee.displayName') AS assignee_name,
        GET_JSON_OBJECT(fields,'$.assignee.emailAddress') AS assignee_email,
        CASE
            WHEN GET_JSON_OBJECT(fields,'$.customfield_11686.value') = "Sim" THEN True
            ELSE False 
        END AS is_reopened,
        CAST(REPLACE(GET_JSON_OBJECT(fields,'$.customfield_10100'), '-0300', '') AS TIMESTAMP) AS ts_first_response,
        GET_JSON_OBJECT(fields,'$.customfield_10529.value') AS support_level,
        GET_JSON_OBJECT(fields,'$.customfield_10659.value') AS priority_defined_by_support,
        CAST(GET_JSON_OBJECT(fields,'$.comment.total') AS INT) AS qtd_comments,
        COALESCE(
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_10222.ongoingCycle.remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2)),
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_10222.completedCycles[0].remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2))
        ) AS sla_time_first_response_hours,
        COALESCE(
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_10660.ongoingCycle.remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2)),
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_10660.completedCycles[0].remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2))
        ) AS sla_hours,	
        COALESCE(
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_11974.ongoingCycle.remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2)),
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_11974.completedCycles[0].remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2))
        ) AS sla_access_approval_hours,
        COALESCE(
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_12006.ongoingCycle.remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2)),
          CAST(CAST(GET_JSON_OBJECT(fields,'$.customfield_12006.completedCycles[0].remainingTime.millis') AS DOUBLE)/3600000 AS DECIMAL(10,2))
        ) AS sla_renewal_hours,
        CAST(GET_JSON_OBJECT(fields,'$.customfield_10202.rating') AS INT) AS satisfaction,
        GET_JSON_OBJECT(fields,'$.customfield_11270.value') AS sub_category,
        GET_JSON_OBJECT(fields,'$.customfield_11300.value') AS incident_type_old,
        GET_JSON_OBJECT(fields,'$.customfield_11442.value') AS software_incident_old,
        GET_JSON_OBJECT(fields,'$.customfield_12008.value') AS incident_computer_os,
        GET_JSON_OBJECT(fields,'$.customfield_11321.value') AS software_access_old,
        GET_JSON_OBJECT(fields,'$.customfield_11302.value') AS software_category_old,
        GET_JSON_OBJECT(fields,'$.customfield_11977') AS access_software_name_others,
        CASE 
          WHEN GET_JSON_OBJECT(fields,'$.customfield_11860.value') = 'Sim' THEN True
          ELSE False 
        END AS is_temporary_access,
        GET_JSON_OBJECT(fields,'$.customfield_11589.value') AS access_software_name,
        GET_JSON_OBJECT(fields,'$.customfield_11693[0].name') AS access_approval_groups,
        GET_JSON_OBJECT(fields,'$.customfield_11476.value') as company,
        GET_JSON_OBJECT(fields,'$.customfield_12455.value') as service_category,
        ROW_NUMBER() OVER (PARTITION BY key ORDER BY GET_JSON_OBJECT(fields,'$.updated') DESC) AS row_num
    FROM
        datalake_jira_clean.issues
    WHERE 
        KEY like 'TI-%'
)
SELECT 
    id,
    id_issue,
    request_type,
    summary,
    issue_description,
    category,
    current_status,
    reporter_name,
    reporter_email,
    creator_name,
    creator_email,
    departament,
    service_location,
    assignee_name,
    assignee_email,
    is_reopened,
    support_level,
    priority_defined_by_support,
    qtd_comments,
    satisfaction,
    sub_category,
    incident_type_old,
    software_incident_old,
    incident_computer_os,
    software_access_old,
    software_category_old,
    company,
    service_category,
    sla_time_first_response_hours,
    sla_hours,
    sla_access_approval_hours,
    sla_renewal_hours,
    access_software_name_others,
    access_software_name,
    access_approval_groups,
    is_temporary_access,
    ts_first_response,
    ts_status_category_changed,
    ts_created,
    ts_resolved,
    ts_updated
FROM
    record_selection
WHERE
    row_num = 1