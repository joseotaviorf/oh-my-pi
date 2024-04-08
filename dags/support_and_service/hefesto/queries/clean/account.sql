SELECT
    id AS id_account,
    account_sid AS id_account_twilio,
    workspace_sid AS id_workspace_twilio,
    workflow_sid AS id_workflow_twilio
FROM
    datalake_hefesto_raw.account
