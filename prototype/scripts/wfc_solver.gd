class_name WFCSolver
extends RefCounted

# A basic Wave Function Collapse solver for surface tiles.
# Given a set of grid coordinates and adjacency rules, assigns a tile to each coordinate.

var grid_coords: Array[Vector3i] = []
var tiles: Dictionary = {} # tile_id -> { "sockets": { dir: socket_id }, "weight": float }
var opposite_sockets: Dictionary = {} # socket_id -> socket_id

func set_grid(coords: Array[Vector3i]):
	grid_coords = coords

func add_tile(tile_id: String, sockets: Dictionary, weight: float = 1.0):
	tiles[tile_id] = { "sockets": sockets, "weight": weight }

func set_opposite_sockets(rules: Dictionary):
	opposite_sockets = rules

func solve() -> Dictionary:
	var result = {}
	var domains = {}
	
	# Initialize domains
	for coord in grid_coords:
		domains[coord] = tiles.keys().duplicate()
		
	var unassigned = grid_coords.duplicate()
	
	while not unassigned.is_empty():
		# Find coordinate with minimum entropy
		var min_entropy = 999999
		var min_coord = Vector3i.ZERO
		var min_index = -1
		
		for i in range(unassigned.size()):
			var coord = unassigned[i]
			var entropy = domains[coord].size()
			if entropy < min_entropy:
				min_entropy = entropy
				min_coord = coord
				min_index = i
				
		if min_entropy == 0:
			# Contradiction, could not solve
			push_error("WFC Contradiction at " + str(min_coord))
			return result
			
		unassigned.remove_at(min_index)
		
		# Collapse: weighted random choice
		var domain = domains[min_coord]
		var total_weight = 0.0
		for t_id in domain:
			total_weight += tiles[t_id].weight
			
		var r = randf() * total_weight
		var chosen_tile = domain[0]
		for t_id in domain:
			r -= tiles[t_id].weight
			if r <= 0:
				chosen_tile = t_id
				break
				
		result[min_coord] = chosen_tile
		domains[min_coord] = [chosen_tile]
		
		# Propagate constraints (simplified, just immediate neighbors)
		_propagate(min_coord, domains)
		
	return result

var dirs = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]

func _propagate(start_coord: Vector3i, domains: Dictionary):
	var stack = [start_coord]
	while not stack.is_empty():
		var curr = stack.pop_back()
		var curr_domain = domains[curr]
		
		for dir in dirs:
			var neighbor = curr + dir
			if not domains.has(neighbor): continue
			
			var neighbor_domain = domains[neighbor]
			var valid_neighbors = []
			
			for n_tile in neighbor_domain:
				var is_valid = false
				for c_tile in curr_domain:
					if _can_connect(c_tile, n_tile, dir):
						is_valid = true
						break
				if is_valid:
					valid_neighbors.append(n_tile)
					
			if valid_neighbors.size() < neighbor_domain.size():
				domains[neighbor] = valid_neighbors
				stack.append(neighbor)

func _can_connect(tile_a: String, tile_b: String, dir_a_to_b: Vector3i) -> bool:
	var sockets_a = tiles[tile_a].sockets
	var sockets_b = tiles[tile_b].sockets
	
	var socket_a = sockets_a.get(dir_a_to_b, "any")
	var socket_b = sockets_b.get(-dir_a_to_b, "any")
	
	if socket_a == "any" and socket_b == "any":
		return true
		
	return opposite_sockets.get(socket_a, "") == socket_b
