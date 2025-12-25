extends Node


func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event.is_action_pressed("click"):
		var role = self.get_meta("role")

		match role:
			"hand":
				var slot = self.get_meta("slot")
				if slot == null:
					push_error("Hand piece clicked but no slot metadata set")
					return
				Globals.piece_selected.emit(self.get_scene_file_path(), slot)

			"board":
				Globals.tile_clicked.emit(self)
				push_warning("Piece clicked without a valid role meta")
