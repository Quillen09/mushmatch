extends Node2D

class HandCard:
	var template: PackedScene
	var owner: int   # 1 for Player One, 2 for Player Two
	var slot: int

const GRID_SIZE := 5
const TILE_SIZE := Vector2(86,86)
const HAND_SIZE = 3
var animating: bool = false
const PUSH_ANIM_TIME := 0.18
const PUSH_EASE := Tween.TRANS_SINE
const PUSH_EASE_TYPE := Tween.EASE_OUT

@onready var origin = $gridOrigin
@onready var p1_scoreLabel: Label = $Control/CanvasLayer/p1Score
@onready var p2_scoreLabel: Label = $Control/CanvasLayer/p2Score
@onready var turn_label: Label = $Control/CanvasLayer/turnLabel


var grid: Array = [] 
var mushroom_scene = preload("res://scenes/mushroom.tscn")
# Player hands and decks
var p1_hand: Array[HandCard] = []
var p2_hand: Array[HandCard] = []
var deck_p1: Array[PackedScene] = [
		preload("res://scenes/red_circle.tscn"),
		preload("res://scenes/orange_circle.tscn"),
		preload("res://scenes/yellow_circle.tscn"),
		preload("res://scenes/green_circle.tscn"),
		preload("res://scenes/blue_circle.tscn"),
		preload("res://scenes/pink_circle.tscn")
]
var deck_p2: Array[PackedScene] = [
		preload("res://scenes/red_circle.tscn"),
		preload("res://scenes/orange_circle.tscn"),
		preload("res://scenes/yellow_circle.tscn"),
		preload("res://scenes/green_circle.tscn"),
		preload("res://scenes/blue_circle.tscn"),
		preload("res://scenes/pink_circle.tscn")
]
var tile_scenes: Array[PackedScene] = []

# Selection state
var selected_card_template: PackedScene = null
var selected_board_tile: Sprite2D = null
var selected_hand_slot: int = -1

# Turn state
var state = Globals.whosPlaying.PLAYERONE

# Swap mode
var swap_mode := false
var swap_first: Sprite2D = null
var swap_second: Sprite2D = null

# anti-cluster history
var recent_draws_p1: Array = []
var recent_draws_p2: Array = []
const RECENT_HISTORY_SIZE := 6 
const PICK_MAX_ATTEMPTS := 12 


func _ready():
	setup_grid()
	deal_p1_hand()
	deal_p2_hand()
	place_mushroom()
	Globals.arrow_clicked.connect(on_arrow_clicked)
	Globals.piece_selected.connect(_on_hand_card_selected)
	Globals.tile_clicked.connect(_on_board_tile_selected)


func setup_grid():
	tile_scenes = [
		preload("res://scenes/red_circle.tscn"),
		preload("res://scenes/orange_circle.tscn"),
		preload("res://scenes/yellow_circle.tscn"),
		preload("res://scenes/green_circle.tscn"),
		preload("res://scenes/blue_circle.tscn"),
	]
	grid.clear()
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for x in range(GRID_SIZE):
		grid.append([])
		for y in range(GRID_SIZE):
			var chosen_scene: PackedScene = null

			# keep trying until find a tile that doesn't match neighbors
			while true:
				var candidate: PackedScene = tile_scenes[rng.randi_range(0, tile_scenes.size() - 1)]
				var candidate_color: String = candidate.resource_path

				var left_ok := true
				var up_ok := true

				# check left neighbor
				if x > 0:
					var left_tile: Sprite2D = grid[x - 1][y]
					if left_tile.get_meta("color") == candidate_color:
						left_ok = false

				# check above neighbor
				if y > 0:
					var up_tile: Sprite2D = grid[x][y - 1]
					if up_tile.get_meta("color") == candidate_color:
						up_ok = false

				if left_ok and up_ok:
					chosen_scene = candidate
					break

			# instantiate chosen tile
			var tile = chosen_scene.instantiate() as Sprite2D
			tile.set_meta("grid_pos", Vector2i(x, y))
			tile.set_meta("role", "board")
			tile.set_meta("color", chosen_scene.resource_path)
			tile.position = origin.position + Vector2(x, y) * TILE_SIZE

			add_child(tile)
			grid[x].append(tile)


func _grid_world_pos(x: int, y: int) -> Vector2:
	return origin.position + Vector2(x, y) * TILE_SIZE


func set_tile(x: int, y: int, node: Sprite2D) -> void:
	grid[x][y] = node
	node.set_meta("grid_pos", Vector2i(x, y))
	node.position = origin.position + Vector2(x, y) * TILE_SIZE


func place_mushroom() -> void:
	var cx = int((GRID_SIZE - 1) / 2)
	var cy = int((GRID_SIZE - 1) / 2)

	# Remove any existing mushroom anywhere to guarantee uniqueness
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var n: Sprite2D = grid[x][y]
			if n and n.has_meta("is_mushroom") and n.get_meta("is_mushroom") == true:
				if n.is_inside_tree():
					n.queue_free()
				grid[x][y] = null

	# If there's a regular tile at the center, remove it so the mushroom is the only node there
	var center_tile: Sprite2D = grid[cx][cy]
	if center_tile:
		if center_tile.is_inside_tree():
			center_tile.queue_free()
		grid[cx][cy] = null

	# Instantiate and place the mushroom (use set_tile so metas and position are correct)
	var mushroom_tile := mushroom_scene.instantiate() as Sprite2D
	mushroom_tile.set_meta("is_mushroom", true)
	mushroom_tile.set_meta("role", "board")
	mushroom_tile.set_meta("color", mushroom_scene.resource_path)

	set_tile(cx, cy, mushroom_tile)
	add_child(mushroom_tile)

	print("[DEBUG] mushroom placed at grid:", cx, cy)

@warning_ignore("shadowed_variable_base_class")
func deal_hand(owner: int, deck: Array, hand: Array, start_x: int) -> void:
	for i in range(hand.size() - 1, -1, -1):
		_remove_sprite_for_slot(owner, hand[i].slot)
	hand.clear()

	# choose which recent history to use
	var recent: Array
	if owner == 1:
		recent = recent_draws_p1
	else:
		recent = recent_draws_p2
	# build current_hand_colors while filling the hand to avoid duplicates in the same hand
	var current_hand_colors: Array = []

	for slot in range(HAND_SIZE):
		var piece_scene: PackedScene = _pick_anticluster(deck, current_hand_colors, recent)
		# create and append HandCard
		var hand_card = HandCard.new()
		hand_card.template = piece_scene
		hand_card.slot = slot
		hand.append(hand_card)

		# spawn sprite visually
		var sprite = piece_scene.instantiate() as Sprite2D
		sprite.set_meta("slot", slot)
		sprite.set_meta("owner", owner)
		sprite.set_meta("role", "hand")
		sprite.set_meta("color", piece_scene.resource_path)
		sprite.position = Vector2(start_x + slot * TILE_SIZE.x, 1097)
		add_child(sprite)

		# record color in current hand and recent history
		current_hand_colors.append(piece_scene.resource_path)
		recent.append(piece_scene.resource_path)

		# trim recent history to configured size
		while recent.size() > RECENT_HISTORY_SIZE:
			recent.remove_at(0)

		print("[DEBUG] Player", owner, "hand slot", slot, ":", piece_scene.resource_path)

	# store recent back to the correct variable
	if owner == 1:
		recent_draws_p1 = recent
	else:
		recent_draws_p2 = recent


func _pick_anticluster(deck: Array, current_hand_colors: Array, recent_draws: Array) -> PackedScene:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# If deck is tiny, just return a random pick
	if deck.size() <= 1:
		return deck[rng.randi_range(0, deck.size() - 1)]

	# find a candidate that is not in current hand and not in recent draws
	var best_candidate: PackedScene = null
	for attempt in range(PICK_MAX_ATTEMPTS):
		var candidate = deck[rng.randi_range(0, deck.size() - 1)]
		var cand_color = candidate.resource_path

		# prefer candidates not in current hand
		var in_hand = cand_color in current_hand_colors
		# prefer candidates not in recent draws
		var in_recent = cand_color in recent_draws

		# immediate accept if neither in hand nor recent
		if not in_hand and not in_recent:
			return candidate

		# keep a candidate that is not in hand
		if not in_hand and best_candidate == null:
			best_candidate = candidate

		# otherwise keep the first candidate
		if best_candidate == null:
			best_candidate = candidate

	# if exit loop, return best_candidate
	return best_candidate


func deal_p1_hand():
	deal_hand(1, deck_p1, p1_hand, 319)


func deal_p2_hand():
	deal_hand(2, deck_p2, p2_hand, 920)


func _on_hand_card_selected(piece_path: String, slot: int) -> void:
	print("[DEBUG] Hand card selected:", piece_path, "slot:", slot, "state:", state)

	var hand   # declare the variable
	@warning_ignore("shadowed_variable_base_class")
	var owner  # track which player owns the hand

	if state == Globals.whosPlaying.PLAYERONE:
		hand = p1_hand
		owner = 1
	else:
		hand = p2_hand
		owner = 2

	if slot < hand.size():
		var card = hand[slot]
		selected_card_template = card.template
		selected_hand_slot = slot
		selected_board_tile = null
		print("[DEBUG] Player", owner, "selected slot", slot, ":", card.template.resource_path)

		if card.template.resource_path.ends_with("pink_circle.tscn"):
			swap_mode = true
			swap_first = null
			swap_second = null
			print("[DEBUG] Pink card selected: swap mode active")
	else:
		print("[DEBUG] Invalid slot selection for Player", owner)


func _on_board_tile_selected(tile: Sprite2D) -> void:
	if not swap_mode:
		selected_board_tile = tile
		selected_card_template = null
		selected_hand_slot = -1
		print("Tile selected at:", tile.get_meta("grid_pos"))
		return

	# Swap mode
	if swap_first == null:
		swap_first = tile
		print("Swap: first tile selected")
	elif swap_second == null:
		swap_second = tile
		print("Swap: second tile selected")
		swap_tiles(swap_first, swap_second)

		@warning_ignore("shadowed_variable_base_class")
		var owner: int
		if state == Globals.whosPlaying.PLAYERONE:
			owner = 1
		else:
			owner = 2

		remove_piece_from_hand(owner, selected_hand_slot, selected_card_template)

		selected_card_template = null
		selected_board_tile = null
		selected_hand_slot = -1
		swap_mode = false
		swap_first = null
		swap_second = null


@warning_ignore("shadowed_variable_base_class")
func _get_hand(owner: int) -> Array:
	if owner == 1:
		return p1_hand
	elif owner == 2:
		return p2_hand
	else:
		return []


@warning_ignore("shadowed_variable_base_class")
func _get_deck(owner: int):
	if owner == 1:
		return deck_p1
	elif owner == 2:
		return deck_p2
	else:
		return null


@warning_ignore("shadowed_variable_base_class")
func _get_start_x(owner: int) -> float:
	if owner == 1:
		return 319.0
	elif owner == 2:
		return 920.0
	else:
		return 0.0


@warning_ignore("shadowed_variable_base_class")
func _remove_sprite_for_slot(owner: int, slot_index: int) -> void:
	for child in get_children():
		if child is Node and child.has_meta("role") and child.get_meta("role") == "hand":
			if child.get_meta("owner") == owner and child.get_meta("slot") == slot_index:
				child.queue_free()
				return


func _spawn_sprite_at_slot(owner: int, slot_index: int, piece: PackedScene) -> void:
	var start_x := _get_start_x(owner)
	var sprite := piece.instantiate() as Sprite2D
	sprite.set_meta("slot", slot_index)
	sprite.set_meta("owner", owner)
	sprite.set_meta("role", "hand")
	sprite.set_meta("scene_path", piece.resource_path)
	sprite.set_meta("color", piece.resource_path)
	sprite.position = Vector2(start_x + slot_index * TILE_SIZE.x, 1097)
	add_child(sprite)


func remove_piece_from_hand(owner: int, slot: int, piece_scene: PackedScene) -> void:
	print("[DEBUG] remove_piece_from_hand owner:", owner, "requested slot:", slot, "piece:", piece_scene.resource_path)
	var hand := _get_hand(owner)
	var deck = _get_deck(owner)
	if hand.size() == 0 or deck == null:
		print("[WARN] invalid owner or empty hand/deck for owner:", owner)
		return

	for i in range(hand.size() - 1, -1, -1):
		var entry := hand[i] as HandCard
		if entry == null:
			continue

		if entry.slot == slot:
			if entry.template and entry.template.resource_path != piece_scene.resource_path:
				print("[DEBUG] slot matches but template differs at index", i, "slot", entry.slot, "template", entry.template.resource_path)
			var removed_slot := entry.slot
			print("[DEBUG] removing hand entry at index", i, "slot", removed_slot, "template", entry.template.resource_path)

			# remove logical entry and keep ordering by inserting replacement at same index
			hand.remove_at(i)

			# remove the visible sprite for that owner+slot
			_remove_sprite_for_slot(owner, removed_slot)

			# create replacement HandCard and insert at same index
			var new_piece := deck.pick_random() as PackedScene
			var new_card := HandCard.new()
			new_card.template = new_piece
			new_card.slot = removed_slot
			hand.insert(i, new_card)

			# spawn replacement sprite at same slot
			_spawn_sprite_at_slot(owner, removed_slot, new_piece)

			print("[DEBUG] Replaced Player", owner, "slot", removed_slot, "with", new_piece.resource_path)
			break


func swap_tiles(tile_a: Sprite2D, tile_b: Sprite2D) -> void:
	if tile_a == null or tile_b == null:
		print("[WARN] swap_tiles called with null tile")
		return
	# Ensure both tiles are still children (defensive)
	if not tile_a.is_inside_tree() or not tile_b.is_inside_tree():
		print("[WARN] swap_tiles: one tile not in scene tree")
		return
	_swap_grid_entries(tile_a, tile_b)
	print("[DEBUG] Tiles swapped and grid updated:", tile_a.get_meta("grid_pos"), "<->", tile_b.get_meta("grid_pos"))


func _swap_grid_entries(tile_a: Sprite2D, tile_b: Sprite2D) -> void:
	if tile_a == null or tile_b == null:
		return
	# read positions
	var pos_a: Vector2i = tile_a.get_meta("grid_pos")
	var pos_b: Vector2i = tile_b.get_meta("grid_pos")
	# swap array entries
	grid[pos_a.x][pos_a.y] = tile_b
	grid[pos_b.x][pos_b.y] = tile_a
	tile_a.set_meta("grid_pos", pos_b)
	tile_b.set_meta("grid_pos", pos_a)
	# swap actual positions so visuals match grid
	var tmp = tile_a.position
	tile_a.position = tile_b.position
	tile_b.position = tmp


func can_push(type: String, index: int, direction: int) -> bool:
	if selected_card_template == null:
		return false

	var selected_color := selected_card_template.resource_path
	if selected_color.ends_with("pink_circle.tscn"):
		return false
	var line: Array = []
	var removed_tile: Sprite2D

	if type == "row":
		for x in range(GRID_SIZE):
			line.append(grid[x][index])
		if direction == 1:
			removed_tile = line[GRID_SIZE - 1]
		else:
			removed_tile = line[0]

	elif type == "column":
		for y in range(GRID_SIZE):
			line.append(grid[index][y])
		if direction == -1:
			removed_tile = line[GRID_SIZE - 1]
		else:
			removed_tile = line[0]

	var removed_color := get_piece_color(removed_tile)

	var has_match := false
	for piece in line:
		if piece == removed_tile:
			continue
		if get_piece_color(piece) == selected_color:
			has_match = true
			break

	if selected_color == removed_color:
		return true
	elif not has_match:
		return true
	else:
		return false


func get_piece_color(tile: Sprite2D) -> String:
	if tile == null:
		return ""
	return tile.get_meta("color") if tile.has_meta("color") else ""


func move_pieces(type: String, index: int, direction: int) -> void:
	if selected_card_template == null:
		print("[DEBUG] Move blocked: no card selected")
		return

	@warning_ignore("shadowed_variable_base_class")
	var owner: int
	if state == Globals.whosPlaying.PLAYERONE:
		owner = 1
	else:
		owner = 2

	if not can_push(type, index, direction):
		print("[DEBUG] Move blocked: push not allowed")
		return

	if type == "row":
		move_row(index, direction)
	elif type == "column":
		move_column(index, direction)

	# Reset selection
	selected_card_template = null
	selected_board_tile = null
	selected_hand_slot = -1


func move_row(row_index: int, direction: int) -> void:
	# Capture selection state so it can't change while we await the tween
	var card_template_local: PackedScene = selected_card_template
	var hand_slot_local: int = selected_hand_slot
	var owner_local: int
	if state == Globals.whosPlaying.PLAYERONE:
		owner_local = 1
	else:
		owner_local = 2

# Defensive: if selection is already null, abort early
	if card_template_local == null:
		print("[WARN] animate push aborted: no selected card template")
		animating = false
		return
		if animating:
			return
		animating = true

	# Defensive bounds
	if row_index < 0 or row_index >= GRID_SIZE:
		animating = false
		return

	# Snapshot current row
	var line: Array = []
	for x in range(GRID_SIZE):
		line.append(grid[x][row_index])

	# Determine removed tile (visual that will slide out)
	var removed_tile: Sprite2D
	if direction == 1:
		removed_tile = line[GRID_SIZE - 1]
	else:
		removed_tile = line[0]

	# Instantiate incoming tile off-grid
	var new_tile := selected_card_template.instantiate() as Sprite2D
	new_tile.set_meta("role", "board")
	new_tile.set_meta("color", selected_card_template.resource_path)
	add_child(new_tile)
	if direction == 1:
		new_tile.position = _grid_world_pos(-1, row_index)
	else:
		new_tile.position = _grid_world_pos(GRID_SIZE, row_index)

	# Create tween and animate positions
	var tween := create_tween()
	tween.set_trans(PUSH_EASE).set_ease(PUSH_EASE_TYPE)
	for x in range(GRID_SIZE):
		var tile: Sprite2D = line[x]
		if tile:
			var target_x := x + direction
			var target_pos := _grid_world_pos(target_x, row_index)
			tween.tween_property(tile, "position", target_pos, PUSH_ANIM_TIME)
	# animate new tile into its target
	var new_target_x := (0 if direction == 1 else GRID_SIZE - 1)
	tween.tween_property(new_tile, "position", _grid_world_pos(new_target_x, row_index), PUSH_ANIM_TIME)

	# Wait for animation to finish
	await tween.finished

	# Update logical grid (update grid array and metas) AFTER visuals moved
	if direction == 1:
		var old_removed = grid[GRID_SIZE - 1][row_index]
		for x in range(GRID_SIZE - 1, 0, -1):
			var moved = grid[x - 1][row_index]
			if moved:
				set_tile(x, row_index, moved)
		set_tile(0, row_index, new_tile)
		if old_removed and old_removed.has_meta("is_mushroom") and old_removed.get_meta("is_mushroom") == true:
			check_mushroom_goal("right")
		if old_removed and old_removed.is_inside_tree():
			old_removed.queue_free()
		
	else:
		var old_removed = grid[0][row_index]
		for x in range(0, GRID_SIZE - 1):
			var moved = grid[x + 1][row_index]
			if moved:
				set_tile(x, row_index, moved)
		set_tile(GRID_SIZE - 1, row_index, new_tile)
		if old_removed and old_removed.has_meta("is_mushroom") and old_removed.get_meta("is_mushroom") == true:
			check_mushroom_goal("left")
		if old_removed and old_removed.is_inside_tree():
			old_removed.queue_free()
		

	# Remove piece from hand now that move completed
	var owner: int
	if state == Globals.whosPlaying.PLAYERONE:
		owner = 1
	else:
		owner = 2
	remove_piece_from_hand(owner_local, hand_slot_local, card_template_local)

	# Reset selection and state
	selected_card_template = null
	selected_board_tile = null
	selected_hand_slot = -1

	_print_grid_state()
	animating = false


func move_column(col_index: int, direction: int) -> void:
	if animating:
		return
	animating = true

	# Capture selection so it can't change while we await the tween
	var card_template_local: PackedScene = selected_card_template
	var hand_slot_local: int = selected_hand_slot
	var owner_local: int
	if state == Globals.whosPlaying.PLAYERONE:
		owner_local = 1
	else:
		owner_local = 2

	if card_template_local == null:
		print("[WARN] animate_column_push aborted: no selected card template")
		animating = false
		return

	# Defensive bounds
	if col_index < 0 or col_index >= GRID_SIZE:
		animating = false
		return

	# Snapshot current column
	var line: Array = []
	for y in range(GRID_SIZE):
		line.append(grid[col_index][y])

	# Determine board parent (ensure new tile uses same parent as existing tiles)
	var board_parent: Node = null
	for x in range(GRID_SIZE):
		for y in range(GRID_SIZE):
			var t = grid[x][y]
			if t and t.get_parent():
				board_parent = t.get_parent()
				break
		if board_parent:
			break
	if board_parent == null:
		board_parent = origin.get_parent() if origin and origin.get_parent() else self

	# Determine removed tile (bottom when pushing up, top when pushing down)
	var removed_tile: Sprite2D
	if direction == 1:
		removed_tile = line[GRID_SIZE - 1]  # bottom removed when pushing up
	else:
		removed_tile = line[0]  # top removed when pushing down

	# Instantiate incoming tile from captured template and parent it correctly
	var new_tile := card_template_local.instantiate() as Sprite2D
	new_tile.set_meta("role", "board")
	new_tile.set_meta("color", card_template_local.resource_path)
	board_parent.add_child(new_tile)

	# Start off-grid (direction semantics: 1 = push up, -1 = push down)
	if direction == 1:
		# push up: new tile comes from below the grid
		new_tile.global_position = _grid_world_pos(col_index, GRID_SIZE)
	else:
		# push down: new tile comes from above the grid
		new_tile.global_position = _grid_world_pos(col_index, -1)

	# Debug: confirm parents and positions
	print("[DEBUG] animate_column_push start col:", col_index, "dir:", direction)
	print(" board_parent:", board_parent, "new_tile parent:", new_tile.get_parent())
	print(" origin:", origin, "origin.pos:", origin.position, "TILE_SIZE:", TILE_SIZE)

	# Create tween and animate global_position for each tile
	var tween := create_tween()
	tween.set_trans(PUSH_EASE).set_ease(PUSH_EASE_TYPE)

	# Visual targets: tiles move by -1 for push up, +1 for push down
	for y in range(GRID_SIZE):
		var tile: Sprite2D = line[y]
		if tile:
			var target_y := y + ( -1 if direction == 1 else 1 )
			var target_pos := _grid_world_pos(col_index, target_y)
			tween.tween_property(tile, "global_position", target_pos, PUSH_ANIM_TIME)

	# New tile target index (where it should land)
	var new_target_y := (GRID_SIZE - 1 if direction == 1 else 0)
	tween.tween_property(new_tile, "global_position", _grid_world_pos(col_index, new_target_y), PUSH_ANIM_TIME)

	# Debug: print start/target for verification
	print("[DEBUG] new_tile start:", new_tile.global_position, "new target index:", new_target_y, "new target pos:", _grid_world_pos(col_index, new_target_y))

	# Wait for animation to finish
	await tween.finished

	# Update logical grid AFTER visuals moved — use the same direction convention
	if direction == -1:
		# push up: removed was bottom; shift source y-1 -> dest y
		var old_removed = grid[col_index][GRID_SIZE - 1]
		for y in range(GRID_SIZE - 1, 0, -1):
			var moved = grid[col_index][y - 1]
			if moved:
				set_tile(col_index, y, moved)
		set_tile(col_index, 0, new_tile)
		if old_removed and old_removed.has_meta("is_mushroom") and old_removed.get_meta("is_mushroom") == true:
			check_mushroom_goal("bottom")
		if old_removed and old_removed.is_inside_tree():
			old_removed.queue_free()
		
	else:
		# push down: removed was top; shift source y+1 -> dest y
		var old_removed = grid[col_index][0]
		for y in range(0, GRID_SIZE - 1):
			var moved = grid[col_index][y + 1]
			if moved:
				set_tile(col_index, y, moved)
		set_tile(col_index, GRID_SIZE - 1, new_tile)
		if old_removed and old_removed.has_meta("is_mushroom") and old_removed.get_meta("is_mushroom") == true:
			check_mushroom_goal("top")
		if old_removed and old_removed.is_inside_tree():
			old_removed.queue_free()
		

	# Remove piece from hand using captured locals
	remove_piece_from_hand(owner_local, hand_slot_local, card_template_local)

	# Reset selection and state
	selected_card_template = null
	selected_board_tile = null
	selected_hand_slot = -1

	_print_grid_state()
	animating = false


# Debugging prints grid colors and nulls
func _print_grid_state() -> void:
	print("[GRID STATE]")
	for y in range(GRID_SIZE):
		var row_str := ""
		for x in range(GRID_SIZE):
			var t: Sprite2D = grid[x][y]
			if t:
				row_str += "[" + str(x) + "," + str(y) + "]=" + str(get_piece_color(t)) + "  "
			else:
				row_str += "[" + str(x) + "," + str(y) + "]=NULL  "
		print(row_str)


func on_arrow_clicked(type: String, index: int, direction: int) -> void:
	move_pieces(type, index, direction)


func _on_end_turn_button_pressed() -> void:
	if state == Globals.whosPlaying.PLAYERONE:
		state = Globals.whosPlaying.PLAYERTWO
		turn_label.text = "Player 2's Turn"
		print("[DEBUG] End turn: now Player Two's turn")
	else:
		state = Globals.whosPlaying.PLAYERONE
		turn_label.text = "Player 1's Turn"
		print("[DEBUG] End turn: now Player One's turn")


func check_mushroom_goal(side: String) -> void:
	if side in Globals.GOAL_SIDES[Globals.whosPlaying.PLAYERONE]:
		Globals.award_point(Globals.whosPlaying.PLAYERONE)
		print("[DEBUG] mushroom exited on", side, "→ Player One scores!")
		p1_scoreLabel.text = "Player 1 score: %d" % Globals.p1_score
		place_mushroom()
		Globals.winCondition()
	elif side in Globals.GOAL_SIDES[Globals.whosPlaying.PLAYERTWO]:
		Globals.award_point(Globals.whosPlaying.PLAYERTWO)
		print("[DEBUG] mushroom exited on", side, "→ Player Two scores!")
		p2_scoreLabel.text = "Player 2 score: %d" % Globals.p2_score
		place_mushroom()
		Globals.winCondition()
