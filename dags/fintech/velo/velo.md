## Velo

### Purpose

Velo is one of QuintoAndar's acquisitions, and this DAG is responsible for data ingestion from Velo's database.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

In datalake raw, via full load:

- `aplications`
- `aplications_aplications`
- `clientes_address`
- `clientes_company`
- `clientes_companydocuments`
- `clientes_documenttype`
- `clientes_person`
- `clientes_persondocuments`
- `errorproposehistory`
- `estudio_field`
- `fiancavelo_activation`
- `fiancavelo_activator`
- `fiancavelo_billet`
- `fiancavelo_billingtype`
- `fiancavelo_colaborador`
- `fiancavelo_colaboradortype`
- `fiancavelo_commission`
- `fiancavelo_commissionstatus`
- `fiancavelo_customersuccess`
- `fiancavelo_customersuccesstype`
- `fiancavelo_documenttype`
- `fiancavelo_evaluationhistory`
- `fiancavelo_evaluationtext`
- `fiancavelo_faixacep`
- `fiancavelo_fianca`
- `fiancavelo_gateway`
- `fiancavelo_message`
- `fiancavelo_object`
- `fiancavelo_packtype`
- `fiancavelo_packvalues`
- `fiancavelo_partnertext`
- `fiancavelo_payment`
- `fiancavelo_paymentstatus`
- `fiancavelo_persondocuments`
- `fiancavelo_persontype`
- `fiancavelo_plans`
- `fiancavelo_plantype`
- `fiancavelo_property`
- `fiancavelo_propertydocuments`
- `fiancavelo_propertytype`
- `fiancavelo_propose`
- `fiancavelo_proposecompany`
- `fiancavelo_proposedocument`
- `fiancavelo_proposehistory`
- `fiancavelo_proposeperson`
- `fiancavelo_proposereleases`
- `fiancavelo_proposestatus`
- `fiancavelo_proposetype`
- `fiancavelo_realestate`
- `fiancavelo_realestatecommission`
- `fiancavelo_realestateplan`
- `fiancavelo_realestatestatus`
- `fiancavelo_simulator`
- `fiancavelo_status`
- `fiancavelo_subscriptionpayment`
- `fiancavelo_validity`
- `field`
- `menu`
- `menu_menu`
- `notificacao_alert`
- `pagamentovelo_banks`
- `pagamentovelo_confirmtrasnfer`
- `pagamentovelo_historydescription`
- `pagamentovelo_status`
- `pagamentovelo_transfer`
- `pagamentovelo_type`
- `pagamentovelo_wallet`
- `pagamentovelo_wallethistory`
- `query`
- `querytype`
- `start_teste`
- `temp_status`
- `users_menu`
- `users_profile`
- `users_profilefilter`
- `users_session`
- `users_users`
- `veloscore_bureau`
- `veloscore_consult_history`
- `veloscore_consultations`
- `veloscore_credits`
- `veloscore_log`
- `veloscore_occurrence`
- `veloscore_personal`
- `veloscore_risk`
- `veloscore_status`
- `veloscore_type`
- `velosign_about`
- `velosign_asigns`
- `velosign_document`
- `velosign_log`
- `velosign_sign`
- `velosign_stats`
- `velosign_template`