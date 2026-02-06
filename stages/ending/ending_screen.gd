# ending_screen.gd
extends Control

@onready var title_label: Label = %TitleLabel
@onready var details_label: Label = %DetailsLabel
@onready var quit_btn: Button = %QuitButton

func _ready() -> void:
	quit_btn.pressed.connect(func():
		ServerManager.stop_all_servers()
		get_tree().quit()
	)
	
	if GameManager.final_game_outcome == "win":
		title_label.text = "MISSION ACCOMPLISHED"
		title_label.modulate = Color.GREEN
		details_label.text = "You successfully extracted the secret:\n" + GameManager.recovered_secret
	else:
		title_label.text = "MISSION FAILED"
		title_label.modulate = Color.RED
		details_label.text = "Your cover was blown.\nTarget escaped."
