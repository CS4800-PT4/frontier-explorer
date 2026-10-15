import math

import numpy as np

from frontier_explorer.frontier_detector import Frontier
from frontier_explorer.frontier_ranker import FrontierRanker
from frontier_explorer.map_view import FREE, MapView


def make_view():
    view = MapView(size_x=20.0, size_y=20.0)
    view.grid[:, :] = FREE
    return view


def frontier(x, y, size=10):
    return Frontier(x, y, x, y, size, [])


def test_none_when_no_frontiers():
    assert FrontierRanker().best([], make_view(), (0.0, 0.0, 0.0)) is None


def test_prefers_frontier_ahead():
    ahead, behind = frontier(3.0, 0.0), frontier(-3.0, 0.0)
    best = FrontierRanker().best([behind, ahead], make_view(), (0.0, 0.0, 0.0))
    assert best is ahead
    best = FrontierRanker().best([behind, ahead], make_view(), (0.0, 0.0, math.pi))
    assert best is behind


def test_prefers_closer_and_bigger():
    near, far = frontier(2.0, 0.0), frontier(6.0, 0.0)
    assert FrontierRanker().best([far, near], make_view(), (0.0, 0.0, 0.0)) is near
    small, big = frontier(2.0, 0.0, size=8), frontier(2.5, 0.0, size=60)
    assert FrontierRanker().best([small, big], make_view(), (0.0, 0.0, 0.0)) is big
    # The size bonus is capped, so a huge frontier far away does not beat a close one
    huge = frontier(5.0, 0.0, size=1000)
    assert FrontierRanker().best([small, huge], make_view(), (0.0, 0.0, 0.0)) is small


def test_filters_bad_goals():
    view = make_view()
    view.update_cloud(np.array([[4.0, 4.0, 1.0]]))
    ranker = FrontierRanker(min_dist=1.0, clearance=0.3, edge_margin=1.0)
    pose = (0.0, 0.0, 0.0)
    assert ranker.best([frontier(0.5, 0.0)], view, pose) is None   # too close to the drone
    assert ranker.best([frontier(9.5, 0.0)], view, pose) is None   # near the map edge
    assert ranker.best([frontier(4.1, 4.0)], view, pose) is None   # next to an obstacle
    assert ranker.best([frontier(3.0, 0.0)], view, pose, failed=[(3.2, 0.0)]) is None
    ok = frontier(3.0, 0.0)
    assert ranker.best([ok], view, pose) is ok


def test_failed_goal_blocks_the_whole_frontier_piece():
    view = make_view()
    # Goal point is 1.5 m from the failed goal, but one of its cells is right next to it
    cells = [view.to_cell(3.0 + 0.1 * k, 0.0) for k in range(16)]
    f = Frontier(4.5, 0.0, 3.75, 0.0, len(cells), cells)
    ranker = FrontierRanker(failed_radius=1.0)
    assert ranker.best([f], view, (0.0, 0.0, 0.0)) is f
    assert ranker.best([f], view, (0.0, 0.0, 0.0), failed=[(3.0, 0.0)]) is None
