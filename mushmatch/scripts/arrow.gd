extends Sprite2D

@export var type = "column"
@export var index = 1
@export var direction = -1

func _on_area_2d_input_event(_viewport: Node, _event: InputEvent, _shape_idx: int) -> void:
	if Input.is_action_just_pressed("click"):
		print("Arrow pressed -> emitting:", type, index, direction)
		Globals.arrow_clicked.emit(type, index, direction)

		#pull index and type to sedn to board
		#to use if statement to tell pieces how to move
