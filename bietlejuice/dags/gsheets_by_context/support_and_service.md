## GSHEETS

### Purpose

This DAG extracts data from Google Sheets files.

If you need information to understand how you can add your sheet, check our [Google Sheets Guide](https://www.notion.so/productquintoandar/Google-Sheets-0c11b1f13b7349918f91c0dec2b7e8f1).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>
  
### Execution Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:

1. Data lake raw:
    - `agendamento_vistoria_entrada`
    - `agendamento_vistoria_saida`
    - `aux_check_photo_sender`
    - `aux_payments_photos`
    - `regional_inspection_q12022`
    - `support_agents_department`
    - `csat_chaves_off_pp`
    - `csat_chaves_onb_iq`
    - `forms_analise_vistoria`
    - `service_city_holidays`
    - `tag_sla_target`
    - `target_service_kpis`
    - `target_support_kpis`
    - `taxonomy_sla`
2. Data lake clean:
    - `aux_check_photo_sender`
    - `aux_payments_photos`
    - `regional_inspection_q1_2022`
    - `schedule_inspection_departure`
    - `schedule_inspection_entry`
    - `support_agents_department`
    - `owner_offboarding_keys_csat`
    - `tenant_onboarding_keys_csat`
    - `inspection_analysis_forms`
    - `service_city_holidays`
    - `tag_sla_target`
    - `target_service_kpis`
    - `target_support_kpis`
    - `taxonomy_sla`
### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>
