class ClusterPermissionEnum:
    """
    Mapping of all permissions to interact with the clusters.
    For details of the scope of each permission type, check the official documentation
        <https://docs.databricks.com/security/access-control/cluster-acl.html>
    """

    ATTACH_TO = (
        "CAN_ATTACH_TO"
    )  # Can attach notebooks to the cluster; but not restart or manage it
    RESTART = "CAN_RESTART"  # Can restart the cluster; but can not manage it
    MANAGE = (
        "CAN_MANAGE"
    )  # Can edit and manage the cluster, also view logs and monitoring tabs
