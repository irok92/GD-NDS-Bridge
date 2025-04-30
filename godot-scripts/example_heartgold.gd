extends Node

var bizhawk: BizHawk.Server

@export var path_bizhawk: String = "C:\\Projects\\GD-NDS-Bridge\\BizHawk\\"

var emulators: Array[BizHawk.Emulator] = []
var emulator_count = 2

func _ready():
	# The path to where config files and other data related to godot should be stored.
	var path_storage: String = "%s\\GodotData\\" % path_bizhawk
	# The emulator executable
	var path_emulator: String = "%s\\EmuHawk.exe" % path_bizhawk
	# Path to the rom file (make sure its patched)
	var path_rom_heart_gold: String = "%s\\HeartGoldPatched.nds" % path_bizhawk
	# The lua script that should be started with the emulator, this case its the tracker script.
	var path_lua_ironmon: String = "%s\\..\\Ironmon-Godot.lua" % path_bizhawk
	var path_config_base: String = "%s\\config.ini" % path_bizhawk
	
	
	# The server spawns and communicates with the emulators,
	bizhawk = BizHawk.Server.new(path_emulator, path_storage, path_config_base, 6900)
	bizhawk.add_service(TestService.new())
	
	# Just spawning X amount of emulators for testing purposes.
	for i in range(0, emulator_count):
		# TODO: Fix configuration generation, loadiog and saving the same config file causes integers to be confused with floats.
		var emulator = bizhawk.create_emulator("HeartGold" + str(i), path_rom_heart_gold, path_lua_ironmon,
			func(config: Dictionary):
				pass
		)

		emulators.append(emulator)

	# Create a table of buttons for actions to pass on.
	for i in range(0, emulator_count):
		# Start Button
		var start_button = Button.new()
		start_button.text = "Emulator %d" % i
		start_button.position = Vector2(i * 160, 0)
		
		# Cause upvalues the index for each button.
		start_button.pressed.connect(func():
			if emulators[i].is_running():
				emulators[i].stop()
				start_button.text = "Emulator %d stopped" % i
			else:
				emulators[i].start()
				start_button.text = "Emulator %d started" % i
				
		)
		add_child(start_button)

		# Some action buttons
		var framelimit_button = Button.new()
		framelimit_button.text = "Toggle Framelimit"
		framelimit_button.position = Vector2(i * 160, 30)
		framelimit_button.pressed.connect(func():
			if emulators[i].is_running():
				bizhawk.send_action("WindowManager", emulators[i].id, "set_framelimit", {"enabled": true})
			else:
				print("Emulator %d is not running" % i)
		)
		add_child(framelimit_button)

func _process(_delta):
	# Required to make the emulators talk.
	bizhawk.update()


func _notification(what):
	# Close all emulators on load.
	if what == Node.NOTIFICATION_WM_CLOSE_REQUEST || what == MainLoop.NOTIFICATION_CRASH:
		bizhawk.quit()
		get_tree().quit()
			

class TestService extends BizHawk.Service:
	func _init():
		super ("Test")

	func on_update():
		if Input.is_action_just_pressed("ui_cancel"):
			print("Cancel pressed")
			broadcast_action("set_framelimit", {"enabled": false})
		if Input.is_action_just_pressed("ui_accept"):
			print("Accept pressed")
			broadcast_action("set_framelimit", {"enabled": true})

	# Notice that the function name is the action name send from the emulator.
	func framelimit_changed(sender, data):
		print("Emulator signaled framelimit changed: ", sender, data)
