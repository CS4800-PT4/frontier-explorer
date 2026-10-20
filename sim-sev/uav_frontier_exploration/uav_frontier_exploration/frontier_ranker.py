from typing import List
import numpy as np
from .frontier import Frontier, ScoredFrontier

class FrontierRanker:
	def __init__(self, dist_weight: float = 2.0, info_weight: float = 1.0):
		self.dist_weight = dist_weight
		self.info_weight = info_weight
		
	def rank(self, frontiers: List[Frontier], current_pose: np.ndarray) -> List[ScoredFrontier]:
		
		if not frontiers:
			return []

		scored = []
		pose_xy = current_pose[:2]
		for f in frontiers:
			dist = np.linalg.norm(f.position - pose_xy)
			info_gain = f.unknown_nearby or f.size
			score = self.info_weight * info_gain - self.dist_weight * dist
			scored.append(ScoredFrontier(frontier=f, score=score))
		
		scored.sort(key=lambda x: x.score, reverse=True)
		return scored
