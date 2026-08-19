SELECT 
  id_record AS sk_record_type
  , COALESCE(id_business_process, "-1") AS sk_business_process
  , name 
  , developer_name 
  , sobject_type
  , namespace_prefix
  , description 
  , is_active 
  , is_person_type
  , created_date AS ts_created
  , last_modified_date AS ts_last_modified
  , NOW() AS ts_load 
 FROM datalake_salesforce_clean.record_type_v2
  WHERE _is_current=True 