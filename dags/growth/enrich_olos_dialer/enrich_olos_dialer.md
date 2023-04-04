## Enrich Olos Dialer

### Purpose

Creates a table that enriches datalake_olos_dialer_clean.attempts_raw_data table information with another data sent by Olos, such as users and campaigns infos.
The goal of this table is to deliver the same structure of data that is delivered by the datalake_wololo_clean.contacts table, because we want to have all the information about the contacts attempts (succeeded or not) that Inside Sales realizes with our prospects.

You might be asking "Well, why you don't use datalake_wololo_clean.contacts instead?". Replicating here what is written on the olos_dialer DAG documentation:

Our outbound contacts with customers are carried out by an internal team and also by third-party companies, and these contacts need a dialer so that they can happen.
QuintoAndar hired the Olos company dialer for that, so we need to ingest the data from these dialings to integrate with our internal data because only with the data coming from Olos we can determine which company acted in a specific dialing and other details.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output table:

- `outbound_attempts_contacts` - a compilation of all contacts attempts realized with our prospects through Olos Dialer.
- `outbound_last_contact` - a compilation of the last contact for each lead/prospect. With this table we want to know what was the operation that had the most recent contact with the prospect.

</details>
