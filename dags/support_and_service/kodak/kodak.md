## Kodak

### Purpose
​
This DAG creates the tables from [Kodak](https://github.com/quintoandar/kodak), a service that stores all media formats at QuintoAndar.
​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables, via **full** load:

1. In datalake raw:
    - `image_inspection_raw`
    - `image_inspection_group_raw`
    - `photo`
    - `photo_aud`
    - `photosphere`
    - `photosphere_aud`
    - `userrevisionentity`
    - `video`
    - `video_aud`

1. In datalake clean:
    - `image_inspection_raw`
    - `image_inspection_group_raw`
    - `photo`
    - `photo_aud`
    - `photo_sphere`
    - `photo_sphere_aud`
    - `user_revision_entity`
    - `video`
    - `video_aud`

This pipeline produces the following output tables, via **incremental** load:

1. In datalake raw:
    - `image_inspection`
    - `image_inspection_group`
    - `image_inspection_group_result`

1. In datalake clean:
    - `image_inspection`
    - `image_inspection_group`
    - `image_inspection_group_result`
​
</details>