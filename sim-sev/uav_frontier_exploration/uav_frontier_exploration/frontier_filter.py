# The Frontier Filter removes frontiers that are too small, too close to obstacles, or clearly unreachable

from typing import List
import numpy as np
from .frontier import Frontier


class FrontierFilter:
    def __init__(self, min_size: int = 1, min_clearance: float = 0.4):
        self.min_size = min_size
        self.min_clearance = min_clearance

    def filter(self, frontiers: List[Frontier], grid: np.ndarray,
               origin: np.ndarray, resolution: float,
               current_pose: np.ndarray) -> List[Frontier]:
        valid = []
        for f in frontiers:
            if f.size < self.min_size:
                continue
            # TODO: optional clearance check around f.position
            # TODO: optional simple reachability (e.g. distance or raycast)
            valid.append(f)
        return valid