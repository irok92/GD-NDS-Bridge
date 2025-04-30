local json = dofile(Paths.FOLDERS.NETWORK_FOLDER .. '/Json.lua')

Godot = {}

Godot.hasUpdatedObject = false
Godot.methods = {}
Godot.socketInitialised = false
Godot.instanceName = os.getenv("EMULATOR_INSTANCE_NAME")
Godot.services = {}
Godot.currentService = nil


local function sendObject(object)
	local json_object = json.encode(object)
	comm.socketServerSend(json_object)
end


function Godot.init()
    -- Sets waitime for each socket to be as little as possible.
    comm.socketServerSetTimeout(1)

end

function Godot.update()

	if Godot.socketInitialised == false then
		if comm.socketServerIsConnected() then
			comm.socketServerSend("BIZZHAWK_SOCKET_VERIFIED")
			sendObject({
				action = "identify",
				sender = Godot.instanceName,
			})
			Godot.socketInitialised = true
			print("Connected")
		end
	end

	if Godot.socketInitialised and comm.socketServerIsConnected() then
		--print("Connected!")
		local response = ""
		-- set to -1 to be unlimited, this can freeze if there is a communication loop!
		local packets_per_frame = -1
	
		repeat
			--print("Response: " .. response)
			response = comm.socketServerResponse()
			if (response ~= "") then
                print("Received: " .. response)
				Godot.relayResponse(response)
			end

			packets_per_frame = packets_per_frame - 1
		until response == "" or packets_per_frame == 0
	end

    for k, service in pairs(Godot.services) do
        if service.onUpdate then
            service.onUpdate()
        end
    end

end

function Godot.relayResponse(response)
    local object = json.decode(response)

    if type(object) ~= "table" then
        print("Invalid object received from socket: " .. response)
        return
    end

    if not object.action then
        print("No action recieved from response: " .. response)
        return
    end

    if not object.sender then
        print("No sender received from response: " .. response)
        return
    end
    
    -- If there is a specific target, send the object to that service

    if object.target then
        local service = Godot.services[object.target]
        if service and type(service[object.action]) == "function" then
            local success, err = pcall(function()
                service[object.action](service, object.sender, object.data)
            end)
            if not success then
                print("Error in call: " .. err)
            end
        else
            print("No service found for target: " .. target)
        end
        return
    end

    for name, service in pairs(Godot.services) do
        if type(service[object.action]) == "function" then
            local success, err = pcall(function()
                service[object.action](service, object.sender, object.data)
            end)
            if not success then
                print("Error in call: " .. err)
            end
        end
    end
end

function Godot.addService(service)
    if type(service) ~= "table" then
        error("Service must be a table")
    end

    if not service.name then
        error("Service must have a name")
    end

    if not Godot.services[service.name] then
        Godot.services[service.name] = service
    else
        print("Service " .. service.name .. " already exists!")
    end
end

function Godot.removeService(serviceName)
    if Godot.services[serviceName] then
        Godot.services[serviceName] = nil
    else
        print("Service " .. serviceName .. " does not exist!")
    end
end


function Godot.sendMessage(target, action, data)
    local message = {
        action = action,
        sender = Godot.instanceName,
        service = Godot.currentService and Godot.currentService.name or nil,
        target = target,
        data = data
    }

    -- Send as an event locally as well if needed.
    local service = Godot.services[target]
    if service and type(service[action]) == "function" then
        Godot.currentService = service
        local success, err = pcall(function()
            service[action](service, message.sender, message.data)
        end)
        if not success then
            print("Error in call: " .. err)
        end
        Godot.currentService = nil
    end
    -- Send back to server.
    sendObject(message)
end

function Godot.broadcastMessage(action, data)
    local message = {
        action = action,
        sender = Godot.instanceName,
        service = Godot.currentService and godot.currentService.name or nil,
        data = data
    }

    -- Send as an event locally as well if needed.
    for name, service in pairs(Godot.services) do
        if type(service[action]) == "function" then
            Godot.currentService = service
            -- PC
            local success, err = pcall(function()
                service[action](service, message.sender, message.data)
            end)
            if not success then
                print("Error in call:" .. err)
            end
            Godot.currentService = nil
        end
    end

    -- Send back to server.
    sendObject(message)
end

return Godot