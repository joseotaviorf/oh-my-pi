## Sales Flow

### Purpose

This DAG imports the tables from [Sales Flow](https://github.com/quintoandar/sales-flow), a service responsible for the management of ForSale's operations after receiving an offer.

### Execution Interval

This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in **datalake raw and clean**, tables via incremental load:
<div style="overflow-x: scroll; height: 200px">

`address_data`  
`address_data_aud`  
`brokerage`     
`brokerage_aud`     
`cash_payment`  
`cash_payment_aud`  
`ccv`   
`ccv_aud`   
`ccv_flow`  
`ccv_flow_aud`  
`ccv_party`     
`ccv_party_aud`     
`ccv_rule`  
`ccv_rule_aud`  
`contact`   
`contact_aud`   
`dilligence`    
`dilligence_aud`    
`dilligence_appointment`    
`dilligence_appointment_aud`    
`house`     
`house_aud`     
`mortgage`  
`mortgage_aud`  
`notary`    
`notary_aud`    
`offer`     
`offer_aud`     
`onboarding`    
`onboarding_aud`    
`payment`   
`payment_aud`   
`rescission`    
`rescission_aud`    
`rev_info`  
`sales_flow`    
`sales_flow_aud`    
`sales_flow_contact_aud`        
`sales_flow_tag_aud`    
`specialist`    
`specialist_aud`    
`tag`   
`tag_aud`   
`user_sample`   
`user_sample_aud`   
`users`     
`users_aud` 
    
</div>

This pipeline produces, in **datalake raw and clean**, tables via full load:
 - `sales_flow_contact`    
 - `sales_flow_tag`

If you need to add a new table, you must update the configuration file `sales_flow_[env]_conf.yml`. By default, all incremental tables use `updated_at` as a date filter, but if you need a different one, add the property `date_filter_column`. If the date filter column isn't actually a date type, you must add the property `unixtime_measure` specifying seconds or milliseconds. If the table_name in the raw layer is different to the one in the clean layer, add the property `clean_table_name`. For an example of all of these properties, search for `revinfo` on the config file.

Then, create the clean query.

If the table isn't found in the configuration file, it will still be ingested to raw incrementally, using `updated_at` as a date filter. It WILL NOT be ingested to clean, even if you add the query.

### Responsible Data Teams
For any questions or concerns about this DAG and data, please contact the Data Engineering Team or
Data Analytics Team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).