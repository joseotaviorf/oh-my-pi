# EMR Local Metrics Monitor

Streamlit app to monitor an EMR cluster (`j-…`): YARN/HDFS metrics, per-node CPU/network/disk charts, and failed-step logs from CloudWatch and S3.

## Prerequisites

- Python 3.10+
- [uv](https://docs.astral.sh/uv/)
- [Weep](https://github.com/Netflix/weep) with ConsoleMe — same setup as `bi-etl-ejuice` `emr-cli`

## Usage

```bash
cd ~/local/emr_monitor
chmod +x run.sh
./run.sh
```

`run.sh` verifies Weep access for **forno** and **prod**, then starts the UI. On first run it creates `~/.weep/weep.yaml` and opens the ConsoleMe challenge in your browser.

Open the URL Streamlit prints (usually http://localhost:8501), then:

1. Enter the cluster ID (`j-…`)
2. Pick **forno** or **prod** in the sidebar
3. Choose a time range (default 3h)
4. Use **Refresh** or enable auto-refresh

Cost estimates read Linux on-demand EC2 and EBS rates from `static_prices.json` (instance types common in bi-etl-ejuice). Use **Update prices from AWS** in the sidebar to refresh that file from the public bulk pricing API (~30s, runs in the background).

Credentials are fetched on demand per environment and refreshed automatically before expiry. No changes to `~/.aws/config` are required.
