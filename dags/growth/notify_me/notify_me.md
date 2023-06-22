## Notify-me

### Purpose
This DAG imports the tables from [Notify-me](https://github.com/quintoandar/notify-me), our service responsible to deliver marketing notifications to our app users.

​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

You can also load a specific date interval by passing a dict as dag_config to DAG Trigger. 
I.E.:

### Outputs
This pipeline produces via incremental ingestion:

1. In datalake raw:
    - `alerts`
    - `alerts_aud`
    - `campaigns`
    - `campaigns_aud`
    - `messages`
    - `messages_aud`
    - `subscriptions`
    - `subscriptions_aud`
    - `user_campaign_preferences`
    - `user_campaign_preferences_aud`
    - `users`
    - `users_aud`
  
2. In datalake clean:
    - `alerts`
    - `alerts_aud`
    - `campaigns`
    - `campaigns_aud`
    - `messages`
    - `messages_aud`
    - `subscriptions`
    - `subscriptions_aud`
    - `user_campaign_preferences`
    - `user_campaign_preferences_aud`
    - `users`
    - `users_aud`
  
### Responsible Data Engineering Team
For any questions or concerns about this DAG, please contact its owner.

</details>