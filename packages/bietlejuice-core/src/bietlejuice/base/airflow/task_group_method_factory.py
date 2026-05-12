from bietlejuice.base.pipeline import LayerEnum


class TaskGroupMethodFactory:
    """
    Factory class to handle method names for each class based on BaseTaskGroup
    """

    @staticmethod
    def get_method_for_build_task_group_from_sql_files(layer_enum):
        """
        Retrieves the correct method name according to the layer for
            method build_task_group_from_sql_files

        :param layer_enum: layer Enum
        :type layer_enum: bietlejuice.base.pipeline.LayerEnum member
        :return: respective method for the supplied layer
        :rtype: method
        """
        layer_enum_member = LayerEnum(layer_enum)

        # By adding these imports to the head of the file it raises
        # error by python circular dependency
        from bietlejuice.base.airflow.task_groups.datalake_task_group import (
            DatalakeTaskGroup,
        )
        from bietlejuice.base.airflow.task_groups.dw_task_group import DWTaskGroup
        from bietlejuice.base.airflow.task_groups.reverse_task_group import (
            ReverseTaskGroup,
        )

        return {
            LayerEnum.CLEAN: DatalakeTaskGroup.build_clean_task_group,
            LayerEnum.ENRICH: DatalakeTaskGroup.build_enrich_task_group,
            LayerEnum.DW_STAGING: DWTaskGroup.build_dw_staging_task_group,
            LayerEnum.DW: DWTaskGroup.build_dw_task_group,
            LayerEnum.METRIC: DatalakeTaskGroup.build_metric_task_group,
            LayerEnum.REVERSE: ReverseTaskGroup.build_reverse_task_group,
        }.get(layer_enum_member)
