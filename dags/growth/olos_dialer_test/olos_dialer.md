# Olos Dialer

## Purpose

Our outbound contacts with customers are carried out by an internal team and also by third-party companies, and these contacts need a dialer so that they can happen.
QuintoAndar hired the [Olos company dialer](https://www.olos.com.br/discador-de-chamadas/) for that, so we need to ingest the data from these dialings to integrate with our internal data because only with the data coming from Olos we can determine which company acted in a certain dialing and other details.

The Olos Company is responsible for sending us the data in JSON format on a daily basis, saving this data at the s3 bucket 5a-discador-olos.
This is the [documentation](https://drive.google.com/drive/folders/1vdSfSNhu3cyvH2HtAmZAsQ6_y1dyHX9V) about the files we extract, sent by Olos.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

## Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

## Outputs

This pipeline produces the following incremental output tables in each layer:

* raw:
  * `datalake_olos_dialer_raw.AgentSupervisor`
  * `datalake_olos_dialer_raw.AgentStateRawData`
  * `datalake_olos_dialer_raw.AttemptsRawData`
  * `datalake_olos_dialer_raw.Campaign`
  * `datalake_olos_dialer_raw.CampaignCustomer`
  * `datalake_olos_dialer_raw.ConfigReasons`
  * `datalake_olos_dialer_raw.Customer`
  * `datalake_olos_dialer_raw.Disposition`
  * `datalake_olos_dialer_raw.DispositionDetail`
  * `datalake_olos_dialer_raw.DispositionPlan`
  * `datalake_olos_dialer_raw.InboundRawData`
  * `datalake_olos_dialer_raw.Info_AgentStatus`
  * `datalake_olos_dialer_raw.Info_CallDirection`
  * `datalake_olos_dialer_raw.Info_CampaignType`
  * `datalake_olos_dialer_raw.Info_DispositionType`
  * `datalake_olos_dialer_raw.Info_PbxDisposition`
  * `datalake_olos_dialer_raw.Info_ReasonType`
  * `datalake_olos_dialer_raw.Info_StatusId`
  * `datalake_olos_dialer_raw.LoginRawData`
  * `datalake_olos_dialer_raw.MailingInformation`
  * `datalake_olos_dialer_raw.OPS_Mailing_LayoutId_4`
  * `datalake_olos_dialer_raw.OPS_Mailing_LayoutId_7`
  * `datalake_olos_dialer_raw.PbxBillingData`
  * `datalake_olos_dialer_raw.QUINTO_ANDAR_20200505_Mailing`
  * `datalake_olos_dialer_raw.Reason`
  * `datalake_olos_dialer_raw.Users`
* clean:
  * `datalake_olos_dialer_clean.agent_state_raw_data`
  * `datalake_olos_dialer_clean.agent_supervisor`
  * `datalake_olos_dialer_clean.attempts_raw_data`
  * `datalake_olos_dialer_clean.campaign`
  * `datalake_olos_dialer_clean.campaign_customer`
  * `datalake_olos_dialer_clean.config_reasons`
  * `datalake_olos_dialer_clean.customer`
  * `datalake_olos_dialer_clean.disposition`
  * `datalake_olos_dialer_clean.disposition_detail`
  * `datalake_olos_dialer_clean.disposition_plan`
  * `datalake_olos_dialer_clean.info_agent_status`
  * `datalake_olos_dialer_clean.info_call_direction`
  * `datalake_olos_dialer_clean.info_campaign_type`
  * `datalake_olos_dialer_clean.info_disposition_type`
  * `datalake_olos_dialer_clean.info_pbx_disposition`
  * `datalake_olos_dialer_clean.info_reason_type`
  * `datalake_olos_dialer_clean.info_status_id`
  * `datalake_olos_dialer_clean.pp_multi_mailing`
  * `datalake_olos_dialer_clean.login_raw_data`
  * `datalake_olos_dialer_clean.mailing_information`
  * `datalake_olos_dialer_clean.mailing`
  * `datalake_olos_dialer_clean.pbx_billing_data`
  * `datalake_olos_dialer_clean.reason`
  * `datalake_olos_dialer_clean.reprocessing_mailing`
  * `datalake_olos_dialer_clean.users`

</details>
