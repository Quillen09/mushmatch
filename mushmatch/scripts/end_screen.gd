extends Control

@onready var winner_label: Label = $winnerLabel
@onready var loser_label: Label = $loserLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Globals.p1_score > Globals.p2_score:
		winner_label.text = "Player 1 Wins! \nScore: %d" % Globals.p1_score
		loser_label.text = "Player 2 Score: %d" % Globals.p2_score
	else:
		winner_label.text = "Player 2 Wins! \nScore: %d" % Globals.p2_score
		loser_label.text = "Player 1 Score: %d" % Globals.p1_score


func _on_play_again_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/board.tscn")


func _on_back_to_title_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
