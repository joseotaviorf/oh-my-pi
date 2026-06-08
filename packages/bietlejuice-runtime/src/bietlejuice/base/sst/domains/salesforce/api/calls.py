"""Salesforce REST ``/query`` helpers: paginated SOQL, optional retries, Spark partition closure.

Lists/pandas only (not Spark DFs). Path from ``configs.salesforce.QUERY_ENDPOINT``.

Gotchas: pagination uses ``base_endpoint + nextRecordsUrl`` (must match your
instance URL shape); results are one in-memory ``list``; page fetches are not
throttled. Retries key off substrings in ``str(exception)`` (fragile; e.g.
timeouts may not match).
"""

import json
import time

import pandas as pd
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.configs.salesforce import QUERY_ENDPOINT
from bietlejuice.base.sst.core.api.request import get_request
from bietlejuice.base.sst.core.utils.time import build_start_end_date
from bietlejuice.base.sst.core.utils.transforms import get_chunks
from bietlejuice.base.sst.domains.salesforce.api.headers import (
    build_authorization_header,
)

logger = QuintoAndarLogger("sst.domains.salesforce.api.calls")


def build_query(columns, table_name, condition):
    cols_query = "\n, ".join(columns)
    query = f"""
    SELECT {cols_query}
    FROM {table_name}
    WHERE {condition}
  """
    return query


def query_all(base_endpoint, access_token, query: str):
    """
    Execute SOQL, follow ``nextRecordsUrl`` until ``done``.

    ``base_endpoint``: instance host URL. Returns merged API ``records`` (dicts,
    usually still with ``attributes``). All pages kept in RAM; no delay between
    page GETs.
    """
    headers = {"Authorization": f"Bearer {access_token}"}
    endpoint = base_endpoint + QUERY_ENDPOINT
    # Nit: Response is a tuple payload, logs
    data, logs = get_request(
        endpoint=endpoint,
        headers=headers,
        params={"q": query},
        timeout=120,
        return_logs=True,
    )
    records = list(data.get("records", []))
    response_logs = [logs]

    while not data.get("done", True):
        data, logs = get_request(
            endpoint=base_endpoint + data.get("nextRecordsUrl"),
            headers=headers,
            timeout=120,
            return_logs=True,
        )
        records.extend(data.get("records", []))
        response_logs.append(logs)

    return records, response_logs


def query_all_with_retry(base_endpoint, access_token, query, max_retries=3):
    """
    Like :func:`query_all`, but retries the whole query on selected failures.

    Args:
        base_endpoint: Same as :func:`query_all` (note: ``query`` comes *before*
            ``access_token`` here, unlike :func:`query_all`).
        access_token: OAuth bearer token.
        query: SOQL string.
        max_retries: Maximum attempts including the first try.

    Returns:
        The same merged ``records`` list as :func:`query_all` on success.

    Raises:
        The last exception if every attempt is exhausted or the error is not
        considered retryable.

    Caveats:
        Retryability is inferred from substrings in ``str(e)`` (HTTP status
        fragments, ``REQUEST_LIMIT_EXCEEDED``, ``SERVER_UNAVAILABLE``). Errors
        that do not contain those tokens are not retried. Sleeps ``2**attempt``
        seconds only *between* retries, not between pagination calls inside a
        single successful :func:`query_all` run.
    """
    for attempt in range(max_retries):
        try:
            return query_all(base_endpoint, access_token, query)

        except Exception as e:
            error = str(e)

            retryable = any(
                x in error
                for x in [
                    "429",
                    "500",
                    "502",
                    "503",
                    "504",
                    "REQUEST_LIMIT_EXCEEDED",
                    "SERVER_UNAVAILABLE",
                ]
            )

            if not retryable or attempt == max_retries - 1:
                raise

            time.sleep(2**attempt)


def build_fetch_partition_closure(base_endpoint, access_token):
    """
    Build a partition function (closure) for Spark ``mapInPandas``-style APIs.

    The returned callable captures ``base_endpoint`` and ``access_token`` for
    the worker lifetime; treat that as sensitive (token in closure scope).

    Returns:
        A function ``fetch_partition_iterator(iterator)`` where ``iterator``
        yields pandas DataFrames. Each row must have columns ``idx`` and
        ``query``. For each row, runs :func:`query_all_with_retry`, strips
        ``attributes`` from each Salesforce record, and emits one output row
        per *record* (not one row per input row when a query returns many
        records).

    Caveats:
        Uses :meth:`pandas.DataFrame.iterrows`, which is slow for very wide or
        large partitions. ``json.dumps(record)`` assumes each record dict is
        JSON-serializable after ``attributes`` is removed. If the query returns
        no records, the partition yields an empty DataFrame for that input row.
        Failures append a single row with ``success=False`` for that ``idx`` /
        ``query``; partial record batches are not represented. Mutates each
        successful ``record`` dict in place via ``pop("attributes")``.
    """

    def fetch_partition_iterator(iterator):
        """Run queries for one Spark partition; see outer factory docstring."""
        for pdf in iterator:
            rows = []
            for _, row in pdf.iterrows():
                idx = row["idx"]
                query = row["query"]
                try:
                    records, logs = query_all_with_retry(
                        base_endpoint=base_endpoint,
                        access_token=access_token,
                        query=query,
                    )

                    # Adding here to avoid serializing at loop level
                    serialized_logs = json.dumps(logs)
                    for record in records:
                        record.pop("attributes", None)
                        rows.append(
                            {
                                "id_record": record.get("Id"),
                                "idx": idx,
                                "api_logs": serialized_logs,
                                "success": True,
                                "error": None,
                                "query": query,
                                "record_json": json.dumps(record),
                            }
                        )

                except Exception as e:
                    rows.append(
                        {
                            "id_record": None,
                            "idx": idx,
                            "api_logs": None,
                            "success": False,
                            "error": str(e),
                            "query": query,
                            "record_json": None,
                        }
                    )

            yield pd.DataFrame(rows)

    return fetch_partition_iterator


def get_change_lst(endpoint, access_token, start_ts, end_ts):
    """
    Hit /updates or /Delete endpoint and retrieve the list of changed records
    between start_ts and end_ts
    """
    headers = build_authorization_header(access_token)
    params = {
        "start": str(start_ts),
        "end": str(end_ts),
    }
    response = get_request(endpoint=endpoint, headers=headers, params=params)
    return response


def paralelize_queries(spark, queries, paralelism):
    """Build a two-column DataFrame (idx, query) and repartition for parallel API work.

    Accepts a list of query strings and materializes them with stable row indices
    so executors can fan out API calls with controlled Spark parallelism.
    """
    return spark.createDataFrame(
        [(idx, query) for idx, query in enumerate(queries)],
        ["idx", "query"],
    ).repartition(paralelism)


def build_query_chunks(id_lst, columns_name, api_entity, chunk_size=200):
    """
    Build a list of queries to be executed against the API based on id_lst and the columns in Salesforce
    """
    chunk_lst = get_chunks(id_lst, chunk_size)
    queries = []
    for chunk in chunk_lst:
        id_cond = ", ".join(f"'{id}'" for id in chunk)
        conditional = f"Id IN ({id_cond})"
        queries.append(
            build_query(
                columns=set(columns_name), table_name=api_entity, condition=conditional
            )
        )
    return queries, chunk_lst


@logger(exclude_return=True, exclude=["endpoint", "access_token"])
def get_updated_lst_system_mod(
    endpoint,
    partition_date,
    api_entity,
    access_token,
    days=1,
):
    """
    Some salesforce Objects doesn't support /updated /deleted endpoint.
    For those we're using SystemModStamp
    """
    logger.info("m=get_updated_lst_system_mod, msg=Retrieving UPDATE and DELETE ID's ")
    start_ts, end_ts = build_start_end_date(partition_date=partition_date, days=days)

    logger.info(
        f"m=get_updated_lst_system_mod, msg=Time range from {start_ts} to {end_ts}"
    )
    soql = f"""
    SELECT Id FROM {api_entity}
    WHERE SystemModstamp >= {start_ts}
      AND SystemModstamp < {end_ts}
  """
    logger.info(f"m=get_updated_lst_system_mod, msg=SOQL: {soql}")
    response, _ = query_all(
        base_endpoint=endpoint, access_token=access_token, query=soql
    )
    id_lst = list(set([item["Id"] for item in response]))
    logger.info(f"m=get_updated_lst_system_mod, msg={len(id_lst)} records found")
    return id_lst


@logger(exclude_return=True, exclude=["endpoint", "access_token"])
def get_updated_deleted_lst(endpoint, partition_date, access_token, days=1):
    updated_endpoint = f"{endpoint}/updated"
    deleted_endpoint = f"{endpoint}/deleted"

    logger.info("m=get_updated_deleted_lst, msg=Retrieving UPDATE and DELETE ID's ")
    start_ts, end_ts = build_start_end_date(partition_date=partition_date, days=days)
    logger.info(
        f"m=get_updated_deleted_lst, msg=Time range from {start_ts} to {end_ts}"
    )

    updated_lst = (
        get_change_lst(
            endpoint=updated_endpoint,
            access_token=access_token,
            start_ts=start_ts,
            end_ts=end_ts,
        ).get("ids")
        or []
    )

    logger.info(
        f"m=get_updated_deleted_lst, msg={len(updated_lst)} UPDATES found at time range"
    )

    deleted_dict = get_change_lst(
        endpoint=deleted_endpoint,
        access_token=access_token,
        start_ts=start_ts,
        end_ts=end_ts,
    )

    deleted_lst = [item["id"] for item in deleted_dict.get("deletedRecords", [])]
    logger.info(
        f"m=get_updated_deleted_lst, msg={len(deleted_lst)} DELETED ROWS found at time range"
    )
    return list(set(deleted_lst + updated_lst))
