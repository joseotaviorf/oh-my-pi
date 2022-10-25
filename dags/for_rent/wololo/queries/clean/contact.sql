SELECT
    id,
    prospectreferenceid AS id_prospect_reference,
    analystid AS id_analyst,
    externalcallid AS id_external_call,
    analystemail as analyst_email,
    channel,
    salescompany AS sales_company,
    phoneoutput AS phone_output,
    phonenumber AS phone_number,
    durationinseconds AS duration_in_seconds,
    contactedat AS ts_contacted
FROM
    datalake_wololo_raw.contact
