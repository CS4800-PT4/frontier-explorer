import math


class FrontierRanker:
    """Picks the frontier to fly to next.

    EGO accepts any goal and never reports failure, so bad goals are filtered out here:
    too close to the drone, too close to an obstacle, near the edge of EGO's map, or near a
    goal that already failed. Of the rest, the lowest cost wins: distance, plus a penalty
    for turning (the camera faces the direction of travel), minus a bonus for big frontiers.
    """

    def __init__(self, min_dist=1.0, clearance=0.3, edge_margin=1.0, heading_weight=2.0,
                 size_weight=0.5, failed_radius=1.0):
        self.min_dist = min_dist
        self.clearance = clearance        # EGO's cloud is already inflated, so this is extra
        self.edge_margin = edge_margin
        self.heading_weight = heading_weight
        self.size_weight = size_weight    # per meter of frontier
        self.failed_radius = failed_radius

    def cost(self, frontier, pose, res):
        x, y, yaw = pose
        dx, dy = frontier.x - x, frontier.y - y
        turn = abs(math.atan2(math.sin(math.atan2(dy, dx) - yaw),
                              math.cos(math.atan2(dy, dx) - yaw)))
        # Size bonus capped at 2 m so one long frontier can't beat everything else
        return (math.hypot(dx, dy) + self.heading_weight * turn
                - self.size_weight * min(frontier.size * res, 2.0))

    def usable(self, frontier, view, pose, failed=()):
        x, y = pose[0], pose[1]
        if math.hypot(frontier.x - x, frontier.y - y) < self.min_dist:
            return False
        if not view.in_bounds(frontier.x, frontier.y, self.edge_margin):
            return False
        if not view.clearance(frontier.x, frontier.y, self.clearance):
            return False
        # A frontier's pieces shift as the map grows, so check every cell of it, not just
        # its goal point, against goals that already failed
        r2 = (self.failed_radius / view.res) ** 2
        for fx, fy in failed:
            if math.hypot(frontier.x - fx, frontier.y - fy) < self.failed_radius:
                return False
            fr, fc = view.to_cell(fx, fy)
            if any((r - fr) ** 2 + (c - fc) ** 2 < r2 for r, c in frontier.cells):
                return False
        return True

    def best(self, frontiers, view, pose, failed=()):
        """pose = (x, y, yaw). Returns the best Frontier, or None if none is usable."""
        best, best_cost = None, None
        for f in frontiers:
            if not self.usable(f, view, pose, failed):
                continue
            c = self.cost(f, pose, view.res)
            if best is None or c < best_cost:
                best, best_cost = f, c
        return best
