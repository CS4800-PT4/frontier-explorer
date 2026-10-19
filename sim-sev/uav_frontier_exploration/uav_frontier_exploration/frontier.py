# data classes

from dataclasses import dataclass
import numpy as np

@dataclass
class Frontier:
	position: np.ndarray
	size: int
	unknown_nearby: int = 0
	id: int = 0
	
@dataclass
class ScoredFrontier:
	frontier: Frontier
	score: float
