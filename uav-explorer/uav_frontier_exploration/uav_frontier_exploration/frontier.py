# data classes

from dataclasses import dataclass, field
import numpy as np

@dataclass
class Frontier:
	position: np.ndarray		# goal [x, y]: frontier cell nearest the centroid
	size: int					# number of cells
	unknown_nearby: int = 0
	id: int = 0
	centroid: np.ndarray = None						# [cx, cy] average of the cells
	cells: list = field(default_factory=list)		# every (row, col) in this frontier
	
@dataclass
class ScoredFrontier:
	frontier: Frontier
	score: float
