-- NDS Ironnon Tracker
-- Created by OnlySpaghettiCode, largely based on the Ironmon Tracker by besteon and other contributors

IronmonTracker = {}

local WatcherService = { name = "Watcher" }

function WatcherService:onUpdate()
	-- Update logic for the watcher service,happens every emu.frameadvance()
end

function WatcherService:set_framelimit(sender, data)
	emu.limitframerate(data.enabled and true or false)
	Godot.sendMessage(sender, "framelimit_changed", { enabled = data.enabled });
end

function WatcherService:close(sender, data)
	Godot.sendMessage(sender, "closing", {})
	client.exit()
end

function IronmonTracker.startTracker()

	local Main = dofile("ironmon_tracker/godot/MainGodot.lua")
	gui.clearImageCache()
	collectgarbage()
	
	local main = Main()
	
	local watcher = { name = "Watcher" }



	Godot.addService(WatcherService)

	main.run()
end

IronmonTracker.startTracker()