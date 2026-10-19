from frontier_explorer.frontier_detector import FrontierDetector
from frontier_explorer.map_view import FREE, OCCUPIED, MapView


def test_no_frontiers_in_unknown_map():
    view = MapView(size_x=5.0, size_y=5.0)
    assert FrontierDetector().detect(view) == []


def test_no_frontiers_when_everything_is_known():
    view = MapView(size_x=5.0, size_y=5.0)
    view.grid[:, :] = FREE
    assert FrontierDetector().detect(view) == []


def test_free_square_has_one_frontier_ring():
    view = MapView(size_x=5.0, size_y=5.0, resolution=0.1)
    view.grid[20:30, 20:30] = FREE          # 10 x 10 free block in unknown space
    frontiers = FrontierDetector(min_size=8).detect(view)
    assert len(frontiers) == 1
    f = frontiers[0]
    assert f.size == 36                     # the outer ring of the block
    assert abs(f.cx - 0.0) < 1e-6 and abs(f.cy - 0.0) < 1e-6
    row, col = view.to_cell(f.x, f.y)
    assert (row, col) in f.cells            # the goal is a real frontier cell


def test_long_frontier_is_split_into_pieces():
    view = MapView(size_x=10.0, size_y=10.0, resolution=0.1)
    view.grid[:50, :] = FREE                # bottom half seen, top half unknown
    frontiers = FrontierDetector(min_size=8, split_size=2.0).detect(view)
    assert len(frontiers) == 5              # one 10 m edge cut into 2 m pieces
    assert all(f.size == 20 for f in frontiers)
    assert sorted(round(f.cx, 2) for f in frontiers) == [-4.0, -2.0, 0.0, 2.0, 4.0]
    assert all(abs(f.x - f.cx) < 0.06 for f in frontiers)  # goal sits on its own piece


def test_walls_split_frontiers_and_small_ones_are_dropped():
    view = MapView(size_x=5.0, size_y=5.0, resolution=0.1)
    view.grid[10:40, 10:40] = OCCUPIED
    view.grid[11:39, 11:39] = FREE
    view.grid[10, 15:25] = FREE             # 10-cell gap in the bottom wall
    view.grid[39, 30:33] = FREE             # 3-cell gap in the top wall
    frontiers = FrontierDetector(min_size=8).detect(view)
    assert len(frontiers) == 1
    assert frontiers[0].size == 10
    assert len(FrontierDetector(min_size=1).detect(view)) == 2
