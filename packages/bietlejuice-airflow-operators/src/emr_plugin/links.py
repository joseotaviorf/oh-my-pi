#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
"""Airflow extra links for EMR runtime logs on S3."""

from __future__ import annotations

from typing import Optional

from airflow.models.baseoperatorlink import BaseOperatorLink

EMR_CLUSTER_LOGS_XCOM_KEY = "quintoandar_emr_cluster_logs_url"
EMR_STEP_LOGS_XCOM_KEY = "quintoandar_emr_step_logs_url"
EMR_STEP_IDS_XCOM_KEY = "quintoandar_emr_step_ids"
EMR_LOG_URI_XCOM_KEY = "quintoandar_emr_log_uri"
EMR_CAPACITY_FALLBACK_XCOM_KEY = "quintoandar_emr_capacity_fallback"


class QuintoAndarEmrClusterLogsLink(BaseOperatorLink):
    """Opens the S3 console at ``{LogUri}/{cluster_id}/``."""

    name = "EMR Cluster Logs"

    def get_link(self, operator, *, ti_key):  # noqa: ARG002
        url = _xcom_link(ti_key, EMR_CLUSTER_LOGS_XCOM_KEY)
        return url or _build_link_from_emr_logs_xcom(ti_key)


class QuintoAndarEmrStepLogsLink(BaseOperatorLink):
    """Opens the S3 console at ``{LogUri}/{cluster_id}/steps/{step_id}/``."""

    name = "EMR Step Logs"

    def get_link(self, operator, *, ti_key):  # noqa: ARG002
        url = _xcom_link(ti_key, EMR_STEP_LOGS_XCOM_KEY)
        if url:
            return url
        return _build_link_from_emr_logs_xcom(
            ti_key, step_id=_first_step_id_from_xcom(ti_key)
        )


def resolve_job_flow_id_from_ti(ti) -> Optional[str]:
    """Resolve EMR cluster id from standard operator XCom keys."""
    job_flow_id = ti.xcom_pull(key="job_flow_id")
    if job_flow_id:
        return job_flow_id

    from airflow.providers.amazon.aws.links.emr import EmrClusterLink, EmrLogsLink

    for key in (EmrLogsLink.key, EmrClusterLink.key):
        conf = ti.xcom_pull(key=key)
        if isinstance(conf, dict) and conf.get("job_flow_id"):
            return conf["job_flow_id"]

    pulled = ti.xcom_pull(task_ids=ti.task_id)
    if isinstance(pulled, str) and pulled.startswith("j-"):
        return pulled
    return None


def _xcom_link(ti_key, xcom_key: str) -> str:
    from airflow.models.xcom import XCom

    if ti_key is None:
        return ""
    value = XCom.get_value(ti_key=ti_key, key=xcom_key)
    return value or ""


def _first_step_id_from_xcom(ti_key) -> Optional[str]:
    from airflow.models.xcom import XCom

    if ti_key is None:
        return None
    step_ids = XCom.get_value(ti_key=ti_key, key=EMR_STEP_IDS_XCOM_KEY)
    if not step_ids:
        return None
    if isinstance(step_ids, str):
        return step_ids
    return step_ids[0] if step_ids else None


def _build_link_from_emr_logs_xcom(ti_key, *, step_id: Optional[str] = None) -> str:
    """Build nested LogUri S3 console URL from provider ``emr_logs`` XCom."""
    from airflow.models.xcom import XCom
    from airflow.providers.amazon.aws.links.emr import EmrLogsLink

    from emr_plugin.s3_log_links import build_emr_logs_console_url_from_conf

    if ti_key is None:
        return ""
    conf = XCom.get_value(ti_key=ti_key, key=EmrLogsLink.key)
    if not isinstance(conf, dict):
        return ""
    return build_emr_logs_console_url_from_conf(conf, step_id=step_id)
