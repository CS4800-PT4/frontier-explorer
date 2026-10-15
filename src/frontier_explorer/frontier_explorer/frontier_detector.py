from dataclasses import dataclass, field

import numpy as np

from frontier_explorer.map_view import FREE, UNKNOWN


@dataclass
class Frontier:
    x: float            # goal point: the frontier cell closest to the centroid
    y: float
    cx: float           # centroid of the cluster (can sit in unknown space)
    cy: float
    size: int           # number of cells
    cells: list = field(default_factory=list)  # (row, col) of every cell


class FrontierDetector:
    """Finds frontiers: free cells that touch unknown cells, grouped into clusters.

    In open space the whole edge of the seen area is one long cluster, and its centroid
    sits back inside seen space. So clusters are cut into square pieces of split_size
    meters, and each piece is its own frontier with its own goal.
    """

    def __init__(self, min_size=8, split_size=2.0):
        self.min_size = min_size
        self.split_size = split_size

    def frontier_mask(self, grid):
        free = grid == FREE
        unknown = grid == UNKNOWN
        # A free cell is a frontier if one of its 4 neighbors is unknown
        near = np.zeros_like(unknown)
        near[1:, :] |= unknown[:-1, :]
        near[:-1, :] |= unknown[1:, :]
        near[:, 1:] |= unknown[:, :-1]
        near[:, :-1] |= unknown[:, 1:]
        return free & near

    def detect(self, view):
        mask = self.frontier_mask(view.grid)
        rows, cols = np.nonzero(mask)
        left = set(zip(rows.tolist(), cols.tolist()))
        frontiers = []
        while left:
            # Flood fill one cluster (8-connected)
            start = left.pop()
            cluster = [start]
            stack = [start]
            while stack:
                r, c = stack.pop()
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        n = (r + dr, c + dc)
                        if n in left:
                            left.remove(n)
                            cluster.append(n)
                            stack.append(n)
            if len(cluster) < self.min_size:
                continue
            for piece in self.split(cluster, view.res):
                if len(piece) >= self.min_size:
                    frontiers.append(self._make_frontier(view, piece))
        return frontiers

    def split(self, cluster, res):
        """Cut a cluster into square tiles of split_size meters (counted from its corner)."""
        k = max(1, int(round(self.split_size / res)))
        r0 = min(r for r, _ in cluster)
        c0 = min(c for _, c in cluster)
        tiles = {}
        for r, c in cluster:
            tiles.setdefault(((r - r0) // k, (c - c0) // k), []).append((r, c))
        return list(tiles.values())

    def _make_frontier(self, view, cluster):
        pts = np.array([view.cell_center(r, c) for r, c in cluster])
        cx, cy = pts.mean(axis=0)
        # The centroid of a curved frontier can land in unknown space, so the goal is
        # the frontier cell nearest to it
        i = int(np.argmin((pts[:, 0] - cx) ** 2 + (pts[:, 1] - cy) ** 2))
        return Frontier(float(pts[i, 0]), float(pts[i, 1]), float(cx), float(cy),
                        len(cluster), cluster)
