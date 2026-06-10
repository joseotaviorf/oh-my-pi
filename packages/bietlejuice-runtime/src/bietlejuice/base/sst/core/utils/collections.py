def get_chunks(data: list, max_size: int) -> list:
    """
    Partition a list into contiguous slices of at most ``max_size`` elements.

    Parameters
    ----------
    data : list
        Sequence to chunk (length may be smaller than ``max_size``).
    max_size : int
        Maximum length of each chunk; must be positive for useful output.

    Returns
    -------
    list
        List of slices, e.g. ``get_chunks([1,2,3,4], 2) -> [[1,2],[3,4]]``.
    """
    return [data[i : i + max_size] for i in range(0, len(data), max_size)]
