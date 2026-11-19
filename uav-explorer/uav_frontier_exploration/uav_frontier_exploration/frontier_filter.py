# The Frontier Filter removes frontiers that are too small, too close to obstacles, or clearly unreachable

from typing import List
import numpy as np
import math
from .frontier import Frontier
from .frontier_detector import MapView


class FrontierFilter:
    def __init__(self, min_dist: float = 1.0, clearance: float = 0.3, edge_margin: float = 1.0, failed_radius: float = 1.0):
        self.min_dist = min_dist            # closer than this = already there (m)
        self.clearance = clearance          # extra gap from obstacles (m), EGO's cloud is already inflated
        self.edge_margin = edge_margin      # stay this far inside EGO's map edge (m)
        self.failed_radius = failed_radius  # skip frontiers this close to a failed goal (m)

    def usable(self, f: Frontier, view: MapView, pose, failed=()) -> bool:
        x, y = pose[0], pose[1]
        gx, gy = float(f.position[0]), float(f.position[1])
        # Too close: drone is basically there already
        if math.hypot(gx - x, gy - y) < self.min_dist:
            return False 
        # Near EGO's map edge (EGO treats outside as a wall)
        if not view.in_bounds(gx, gy, self.edge_margin):
            return False
        # Obstacle within clearance of the goal
        if not view.clearance(gx, gy, self.clearance):
            return False
        # Near a goal that already failed: check the goal point and every cell
        r2 = (self.failed_radius / view.res) ** 2
        for fx, fy in failed:
            if math.hypot(gx - fx, gy - fy) < self.failed_radius:
                return False
            fr, fc = view.to_cell(fx, fy)
            if any((r - fr) ** 2 + (c - fc) ** 2 < r2 for r, c in f.cells):
                return False
        return True

    def filter(self, frontiers: List[Frontier], view: MapView, pose, failed=()) -> List[Frontier]:
            # Keep only the frontiers that pass every usuable() check
            return [f for f in frontiers if self.usable(f, view, pose, failed)]