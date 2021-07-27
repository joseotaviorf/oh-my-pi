## Kill Queue

### Purpose

Load database kill_queue (MySQL), a reservations application database.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table for both our raw and clean layers:

- `charge_aud`
- `charge`
- `house_aud`
- `house`
- `rent_flow`
- `rent_flow_aud`
- `reservation`
- `reservation_aud`
- `rev_info`
- `user`

### Responsible Data Team

For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>