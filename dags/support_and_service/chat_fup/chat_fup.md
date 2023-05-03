## Chat Fup

### Purpose

Extraction of [Chat FUP](https://github.com/quintoandar/chatfup) tables into data lake. Chat FUP is a service to manage followups for whatsapp chats.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables in the clean layer:

- `chats_chat`
- `django_content_type`
- `django_migrations`
- `health_check_db_testmodel`
- `surveys_answer`
- `surveys_survey`

</details>
