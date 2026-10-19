import math

import numpy as np

from frontier_explorer.frontier_detector import FrontierDetector
from frontier_explorer.frontier_ranker import FrontierRanker
from frontier_explorer.map_view import MapView


def fly(view, poses):
    for x, y, yaw in poses:
        view.update_cloud(np.zeros((0, 3)))
        view.update_pose(x, y, 1.0, yaw)
        view.sweep()


def best_angle(view, x, y, yaw):
    frontiers = FrontierDetector().detect(view)
    best = FrontierRanker().best(frontiers, view, (x, y, yaw))
    assert best is not None
    a = math.atan2(best.y - y, best.x - x) - yaw
    return abs(math.atan2(math.sin(a), math.cos(a)))


def test_open_space_goal_is_ahead_after_hover():
    view = MapView()
    fly(view, [(0.0, 0.0, 0.0)])
    assert best_angle(view, 0.0, 0.0, 0.0) < math.radians(40)


def test_open_space_goal_is_ahead_after_flying_straight():
    view = MapView()
    fly(view, [(x, 0.0, 0.0) for x in np.arange(0.0, 6.01, 0.5)])
    assert best_angle(view, 6.0, 0.0, 0.0) < math.radians(40)


def test_wall_ahead_sends_goal_around_it():
    view = MapView()
    wall = np.column_stack([np.full(40, 3.0), np.arange(-1.0, 1.0, 0.05), np.ones(40)])
    view.update_cloud(wall)
    view.update_pose(0.0, 0.0, 1.0, 0.0)
    view.sweep()
    frontiers = FrontierDetector().detect(view)
    best = FrontierRanker().best(frontiers, view, (0.0, 0.0, 0.0))
    assert best is not None
    assert view.clearance(best.x, best.y, 0.3)
    assert abs(best.y) > 0.9 or best.x < 3.0   # not behind the wall
