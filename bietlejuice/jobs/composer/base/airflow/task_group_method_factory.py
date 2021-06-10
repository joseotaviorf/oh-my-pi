from bietlejuice.jobs.composer.base.pipeline import LayerEnum


class TaskGroupMethodFactory(object):
    """
    Factory class to handle method names for each class based on BaseTaskGroup
    """

    @staticmethod
    def get_method_for_build_task_group_from_sql_files(layer_enum):
        """
        Retrieves the correct method name according to the layer for
            method build_task_group_from_sql_files

        :param layer_enum: layer Enum
        :type layer_enum: bietlejuice.jobs.composer.base.pipeline.LayerEnum member
        :return: respective method for the supplied layer
        :rtype: method
        """
        if layer_enum not in (
            LayerEnum.CLEAN,
            LayerEnum.ENRICH,
            LayerEnum.DW_STAGING,
            LayerEnum.DW,
        ):
            raise ValueError(
                "m=get_method_for_build_task_group_from_sql_files,"
                f" layer={layer_enum}, msg=invalid layer"
            )

        return TaskGroupMethodFactory._dispatch_dict_for_build_task_group_from_sql_files(
            layer_enum
        )

    @staticmethod
    def _dispatch_dict_for_build_task_group_from_sql_files(layer_enum):
        """
        Maps methods according to layer

        :param layer_enum: layer Enum
        :type layer_enum: bietlejuice.jobs.composer.base.pipeline.LayerEnum member
        :return: respective method for the supplied layer
        :rtype: method
        """
        # By adding these imports to the head of the file it raises
        # error by python circular dependency
        from bietlejuice.jobs.composer.dags.base.datalake_task_group import (
            DatalakeTaskGroup,
        )
        from bietlejuice.jobs.composer.dags.base.dw_task_group import DWTaskGroup

        return {
            LayerEnum.CLEAN: DatalakeTaskGroup.build_clean_task_group,
            LayerEnum.ENRICH: DatalakeTaskGroup.build_enrich_task_group,
            LayerEnum.DW_STAGING: DWTaskGroup.build_dw_staging_task_group,
            LayerEnum.DW: DWTaskGroup.build_dw_task_group,
        }.get(layer_enum)
