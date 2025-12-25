extends Node

signal arrow_clicked(type: String, index: int, direction: int)
signal piece_selected(piece_path: String, slot)
signal tile_clicked(tile: Sprite2D)
var p1_score: int = 0
var p2_score: int = 0
enum whosPlaying { PLAYERONE, PLAYERTWO }
const GOAL_SIDES = {
	whosPlaying.PLAYERONE: ["left", "bottom"],
	whosPlaying.PLAYERTWO: ["top", "right"]
}

func award_point(player):
	if player == whosPlaying.PLAYERONE:
		p1_score += 1
	else:
		p2_score += 1
		
func winCondition():
	if p1_score == 7 or p2_score == 7:
		get_tree().change_scene_to_file("res://scenes/end_screen.tscn")
