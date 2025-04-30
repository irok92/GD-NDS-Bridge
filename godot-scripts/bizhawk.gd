class_name BizHawk

const BIZZHAWK_SOCKET_VERIFIED = "24 BIZZHAWK_SOCKET_VERIFIED"


class Server extends RefCounted:
	var emulator_path: String
	var storage_path: String
	var config_path: String
	var tcp_server: TCPServer
	var base_port: int = 6900
	var connections: Array[Connection]

	# Keeps internal references of the runned emulator for update loops.
	var emulators: Array[Emulator]
	var emulator_map: Dictionary

	# Keeps internal references of the services so we can send and receive messages.
	var services: Array[Service]
	var service_map: Dictionary


	func _init(_emulator_path: String, _storage_path: String, _config_path: String, port: int = 6900):
		base_port = port
		storage_path = _storage_path
		emulator_path = _emulator_path
		config_path = _config_path
		tcp_server = TCPServer.new()
		tcp_server.listen(port)


	func update():
		var new_connection = tcp_server.take_connection()
		while new_connection != null:
			if new_connection:
				connections.append(Connection.new(self, new_connection))
			
			new_connection = tcp_server.take_connection()

		var connections_to_remove = []
		for connection in connections:
			if !connection.update():
				connections_to_remove.append(connection)

		for connection in connections_to_remove:
			connections.erase(connection)
			if connection != null:
				print("Connection removed: ", connection.emulator.id)
				connection.disconnect_socket()

		for service in services:
			service.on_update()

	func create_emulator(
		name: String,
		rom_path: String,
		lua_path: String,
		config_mutator: Callable,
		environment: Dictionary = {},
	) -> Emulator:
		# var config_name = gen_new_config(config_path, name, config_mutator)
		# Create a new emulator instance, with a socket and others variables.
		var emulator = Emulator.new(self, name, emulator_path, [
			"--socket-ip=%s" % "127.0.0.1",
			"--socket-port=%s" % base_port,
			"--lua=%s" % lua_path,
			"--chromeless",
			# TODO: Config file gen isnt really working as intended, maybe use a manual file instead and copy one from a base if its not found.
			#"--config=%s" % config_name,
			rom_path
		], environment)

		emulators.append(emulator)
		emulator_map[name] = emulator

		return emulator

	func quit():
		for connection in connections:
			connection.disconnect_socket()

		for emulator in emulators:
			emulator.stop()

		# Call Cleanup on all services.
		for service in services:
			if service.has_method("cleanup"):
				service.call("cleanup")

		if tcp_server:
			tcp_server.stop()
			tcp_server = null

		return true


	func gen_new_config(config_path: String, config_name: String, config_mutator: Callable) -> String:
		var config = FileAccess.get_file_as_string(config_path)
		if config == "":
			print("Config file not found: ", config_path)
			return ""

		var config_json = JSON.parse_string(config)
		if config_json == null:
			print("Config file is not valid JSON: ", config_path)
			return ""

		config_mutator.call(config_json)

		var config_string = JSON.stringify(config_json, "\t", false, false)
		var config_destination = "%s\\%s.ini" % [self.storage_path, config_name]

		var file = FileAccess.open(config_destination, FileAccess.WRITE)
		file.store_string(config_string)
		file.close()
		return config_destination

	func add_service(service: Service) -> Service:
		service._set_server(self)
		services.append(service)
		service_map[service.name] = service
		return service

	func remove_service(service_name: Service) -> Service:
		var service = service_map[service_name]
		if service:
			services.erase(service)
			service_map.erase(service_name)
			return service

		return null

	func send_action(service: String, target: String, action: String, data: Variant):
		var emulator = emulator_map[target]
		if emulator:
			if emulator.connection:
				emulator.connection.send_object({
					"action": action,
					"service": service,
					"sender": "server",
					"data": data
				})
			else:
				print("Target connection not found: ", target)

		pass

	func relay_action_to_services(message: Variant):
		for service in services:
			if message.has("action"):
				service.on_action(
					message["action"],
					message["sender"],
					message["data"] if message.has("data") else null
				)

	func broadcast_action(service: String, action: String, data: Variant):
		for connection in connections:
			if connection.emulator:
				connection.send_object({
					"action": action,
					"service": service,
					"sender": "server",
					"data": data
				})
		pass


class Connection extends RefCounted:
	var tcp_stream: StreamPeerTCP
	var partial_message: String = ""
	var handshaked = false
	var bytes_to_read: int = -1
	var server: Server = null
	var emulator: Emulator = null

	func _init(_server: Server, _connection: StreamPeerTCP):
		server = _server
		tcp_stream = _connection
		tcp_stream.set_no_delay(true)


	func _try_handshake() -> bool:
		if tcp_stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				# Only read if the buffer is larger than the assigned size.
			if tcp_stream.get_available_bytes() >= len(BIZZHAWK_SOCKET_VERIFIED):
				var data = tcp_stream.get_string(len(BIZZHAWK_SOCKET_VERIFIED))
				
				if data == BIZZHAWK_SOCKET_VERIFIED:
					print("Handshaked verified.")
					return true
				else: # Deny requests that doesnt match the initial handshake.
					tcp_stream.disconnect_from_host()
					return false
		return false

	func is_alive() -> bool:
		return tcp_stream.get_status() == StreamPeerTCP.STATUS_CONNECTED

	func send_object(message: Variant) -> bool:
		return send_message(JSON.stringify(message))

	func send_message(message: String) -> bool:
		if is_alive():
			tcp_stream.put_data(("%s %s" % [len(message), message]).to_ascii_buffer())
			return true
		return false

	func read_object() -> Variant:
		var message = read_message()
		if message:
			return JSON.parse_string(message)
		return null

	func read_message() -> String:
		# If we dont have a connection, we dont have a message.
		if tcp_stream == null:
			return ""
		
		if tcp_stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return ""

		var available_bytes = tcp_stream.get_available_bytes()
		# Keep adding to the partial string until we have enough bytes to read the message or the length.
		if available_bytes > 0:
			partial_message += tcp_stream.get_string(available_bytes)
		
		if partial_message.is_empty():
			return ""
		
		# basically -1 means read the length of the message.
		if bytes_to_read < 0:
			# We need to find the space to know where the length ends.
			var space_pos = partial_message.find(" ")
			
			# If we dont find a space, just treat it as no message yet.
			if space_pos == -1:
				return ""

			# we split the part of the message for the length then convert it to a number.
			var length_str = partial_message.substr(0, space_pos)
			bytes_to_read = length_str.to_int()

			# Dont forget to add the length of the space.
			partial_message = partial_message.substr(space_pos + 1)
		
		# If we have enough bytes to read the message, we can return a complete message.
		if partial_message.length() >= bytes_to_read:
			var complete_message = partial_message.substr(0, bytes_to_read)
			partial_message = partial_message.substr(bytes_to_read)
			bytes_to_read = -1
			
			return complete_message

		return ''

	# returns false if the connection needs to be stopped.
	func update() -> bool:
		if !tcp_stream:
			return false

		if tcp_stream.poll() != OK:
			disconnect_socket()
			return false

		if !handshaked:
			handshaked = _try_handshake()
			return true

		
		var message = read_object()
		while message:
			print("Recieved Message: ", message)
			
			match message:
				{"action": "identify", "sender": var sender}:
					print("Identified again: ", sender)
					if server.emulator_map.has(sender):
						# We need to bind the connection to the emulator.
						emulator = server.emulator_map[sender]
						emulator.bind_connection(self)
					else:
						print("Emulator not found: ", sender)
						return false
			
			server.relay_action_to_services(message)

			message = read_object()


		return true

	func disconnect_socket():
		if tcp_stream:
			tcp_stream.disconnect_from_host()
			tcp_stream = null

		return true


class Emulator extends RefCounted:
	var process: int = -1
	var id: String = ""
	var connection: Connection = null
	var arguments: Array[String] = []
	var emulator_path: String = ""
	var environment: Dictionary = {}
	var server: Server = null

	func _init(
		_server: Server,
		_id: String,
		_emulator_path: String,
		_arguments: Array[String],
		_environment: Dictionary):
		id = _id
		server = _server
		emulator_path = _emulator_path
		arguments = _arguments
		environment = _environment
	
	func is_running():
		return process != -1

	func start():
		var env_to_revert = {}
		var env_to_unset = []

		# add instance variable to the environment
		environment["EMULATOR_INSTANCE_NAME"] = id

		# Environment variables are inherited from the parent process.
		# We need to revert the environment variables to the original state,
		if environment.size() > 0:
			for key in environment.keys():
				# Save the current environment to revert it later.
				if OS.has_environment(key):
					env_to_revert[key] = OS.get_environment(key)
				else: # Since it doesnt exist, we need to unset it later.
					env_to_unset.append(key)

				OS.set_environment(key, environment[key])
				
		
		if process != -1:
			return false
		
		process = OS.create_process(emulator_path, arguments)

		# Revert the environment variables to the original state.
		for key in env_to_revert.keys():
			OS.set_environment(key, env_to_revert[key])

		# Unset the environment variables that wasnt set before.
		for key in env_to_unset:
			OS.unset_environment(key)

		if process == -1:
			return false

		
		return true

	func bind_connection(_connection: Connection):
		connection = _connection
		return true

	func restart():
		stop()
		return start()
	
	func stop():
		if connection:
			connection.disconnect_socket()
			connection = null

		if process != -1:
			OS.kill(process)
			process = -1
			return true

		return false


# A service is just a module of code that recieves and sends messages.
# A service also can store and load state from disk in form of an object.
class Service extends RefCounted:
	var name: String
	var server: Server

	func _init(_name: String):
		name = _name

	func _set_server(_server: Server):
		server = _server;

	func send_action(target: String, action: String, data: Variant):
		if server != null:
			server.send_action(self.name, target, action, data)

	func broadcast_action(action, data):
		if server != null:
			server.broadcast_action(self.name, action, data)
	
	func on_action(action: String, sender: String, data: Variant):
		if self.has_method(action):
			self.call(action, sender, data)

	func on_update():
		assert(false, "Not inherited.")
