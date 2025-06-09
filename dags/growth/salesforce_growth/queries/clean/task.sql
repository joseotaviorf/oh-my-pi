SELECT
    Id AS id_task_salesforce,
    CreatedDate AS date_creation,
    OwnerId AS id_analyst_salesforce,
    ActivityDate AS date_deadline,
    CompletedDateTime AS date_conclusion,
    Subject AS subject,
    Status AS status_conclusion,
    Resultado_FUP__c AS status,
    WhoId AS id_lead,
    Type AS type,
    dt_updated,
    year,
    month,
    day
FROM
    datalake_salesforce_growth_raw.task
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')