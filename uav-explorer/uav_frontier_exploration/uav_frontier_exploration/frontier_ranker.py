#FrontierRanker: scores usable frontiers by cost (lower = better) and sorts them

import math
from typing import List
import numpy as np
from .frontier import Frontier, ScoredFrontier

class FrontierRanker:
	def __init__(self, heading_weight: float = 2.0, size_weight: float = 0.5, max_size_bonus: float = 2.0):
		self.heading_weight = heading_weight	# cost per radian of turning
		self.size_weight = size_weight			# bonus per meter of frontier
		self.max_size_bonus = max_size_bonus	# cap (m) so one long edge can't win everything

	def cost(self, f: Frontier, pose, res: float) -> float:
		x, y, yaw = pose
		dx, dy = float(f.position[0]) - x, float(f.position[1]) - y
		# Angle the drone must turn to face the frontier, wrapped to 0..pi
		heading = math.atan2(dy, dx)
		turn = abs(math.atan2(math.sin(heading - yaw), math.cos(heading - yaw)))
		# Size bonus in meters, capped
		bonus = min(f.size * res, self.max_size_bonus)
		return math.hypot(dx, dy) + self.heading_weight * turn - self.size_weight * bonus



	def rank(self, frontiers: List[Frontier], pose, res: float) -> List[ScoredFrontier]:
		# Score every (already filtered) frontier, lower cost first 
		scored = [ScoredFrontier(frontier=f, score=self.cost(f, pose, res)) for f in frontiers]
		scored.sort(key=lambda s: s.score)
		return scored
