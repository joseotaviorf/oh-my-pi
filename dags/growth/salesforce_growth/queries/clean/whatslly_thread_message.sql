SELECT
    Id AS id_salesforce,
    whatslly__Message_ID__c AS id_message_whatslly,
    whatslly__Message__c AS message,
    whatslly__Direction__c AS direction,
    whatslly__Datetime__c AS datetime,
    whatslly__Is_Past_24h__c AS is_past_24h,
    whatslly__Is_Sent__c AS is_sent,
    whatslly__Recipient_Phone__c AS recipient_phone,
    whatslly__Sender_Phone__c AS sender_phone,
    whatslly__Related_Lead__c AS id_lead,
    whatslly__Whatslly_Person_Id__c AS id_person,
    OwnerId AS id_analyst_salesforce,
    dt_updated,
    year,
    month,
    day
FROM
    datalake_salesforce_growth_raw.whatslly_thread_message
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')