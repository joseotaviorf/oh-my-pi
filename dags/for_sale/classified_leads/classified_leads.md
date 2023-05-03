## Classified Leads
### Purpose

ClassifiedsResponder is a Database we use to store our contract history we have when dealing with Classifieds Leads (A lead which comes from one of our Classifieds like Criteo). This DAG ingests this database into our raw flow (until clean).

<details>
    <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there are the following output tables for both our raw and clean layers:

- `leads_contact`
- `leads_reply`
- `leads_reply_email`
- `leads_reply_whatsapp`

</details>
