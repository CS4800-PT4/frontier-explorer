from typing import List
import numpy as np
from .frontier import Frontier


class FrontierDetector:
    def __init__(self, min_size: int = 5):
        self.min_size = min_size

    def detect_from_cloud(self, points: np.ndarray, pose: np.ndarray) -> List[Frontier]:
        """
        Detect frontiers from a PointCloud2 of occupied points.
        points: (N, 3) array of XYZ occupied points
        pose:   (3,) current UAV position
        """
        if points is None or len(points) == 0:
            return []

        # Simple placeholder: return the occupied point farthest from the UAV
        # Replace this block with your real frontier logic later
        dists = np.linalg.norm(points[:, :2] - pose[:2], axis=1)
        idx = np.argmax(dists)
        pt = points[idx]

        return [Frontier(
            position=np.array([pt[0], pt[1]]),
            size=1,
        )]

    # ---------------------------------------------------------------------------
    # LEGACY: OccupancyGrid-based frontier detection.
    # Not used while the EGO planner publishes PointCloud2.
    # Kept only as a fallback if an OccupancyGrid source becomes available.
    # ---------------------------------------------------------------------------
    def detect(self, grid: np.ndarray, origin: np.ndarray, resolution: float,
               current_pose: np.ndarray) -> List[Frontier]:
        """
        Detect frontiers: free cells that border unknown cells.
        grid: 2D occupancy grid (0 = free, 100 = occupied, -1 = unknown)
        origin: [x, y] of grid origin in world frame
        resolution: meters per cell
        """
        if grid is None or grid.size == 0:
            return []

        height, width = grid.shape
        frontiers = []
        visited = np.zeros_like(grid, dtype=bool)

        # 4-connected neighbors
        neighbors = [(-1, 0), (1, 0), (0, -1), (0, 1)]

        def is_frontier_cell(r: int, c: int) -> bool:
            if grid[r, c] != 0:          # must be free
                return False
            for dr, dc in neighbors:
                nr, nc = r + dr, c + dc
                if 0 <= nr < height and 0 <= nc < width and grid[nr, nc] == -1:
                    return True
            return False

        def flood_fill(start_r: int, start_c: int) -> List[tuple]:
            cells = []
            stack = [(start_r, start_c)]
            visited[start_r, start_c] = True
            while stack:
                r, c = stack.pop()
                cells.append((r, c))
                for dr, dc in neighbors:
                    nr, nc = r + dr, c + dc
                    if (0 <= nr < height and 0 <= nc < width and
                            not visited[nr, nc] and is_frontier_cell(nr, nc)):
                        visited[nr, nc] = True
                        stack.append((nr, nc))
            return cells

        # Scan for frontier seeds
        for r in range(height):
            for c in range(width):
                if visited[r, c] or not is_frontier_cell(r, c):
                    continue
                cells = flood_fill(r, c)
                if len(cells) < self.min_size:
                    continue

                # Centroid in world coordinates
                rows = np.array([cell[0] for cell in cells])
                cols = np.array([cell[1] for cell in cells])
                world_x = origin[0] + (cols.mean() + 0.5) * resolution
                world_y = origin[1] + (rows.mean() + 0.5) * resolution

                frontiers.append(Frontier(
                    position=np.array([world_x, world_y]),
                    size=len(cells),
                    cells=cells
                ))

        return frontiers