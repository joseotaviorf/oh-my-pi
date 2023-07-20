## Mission Control

### Purpose

Load database mission_control (MySQL) responsible for the onboarding and ongoing journey of our tenants and landlords.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw and clean layers.
Both layer the ingestion is via incremental load.

Raw:
- `onboarding`
- `onboardingaction`
- `onboardingbill`
- `onboardingtask`
- `onboardingtasktypes`

Clean:
- `onboarding`
- `onboarding_action`
- `onboarding_bill`
- `onboarding_task`
- `onboarding_task_types`

</details>
