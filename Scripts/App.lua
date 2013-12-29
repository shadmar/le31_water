--This function will be called once when the program starts
function App:Start()
	
	--Set the application title
	self.title="MyGame"
	
	--Create a window
	self.window=Window:Create(self.title)
	self.window:HideMouse()
	
	--Create the graphics context
	self.context=Context:Create(self.window,0)
	if self.context==nil then return false end
	
	--Create a world
	self.world=World:Create()
	
	--Load a map
	local mapfile = System:GetProperty("map","Maps/start.map")
	if Map:Load(mapfile)==false then return false end
	
	return true
end

--This is our main program loop and will be called continuously until the program ends
function App:Loop()
	
	--If window has been closed, end the program
	if self.window:Closed() or self.window:KeyDown(Key.Escape) then return false end
	
	--Update the app timing
	Time:Update()
	
	--Update the world
	self.world:Update()
	
	--Render the world
	self.world:Render()
	
	--Render statistics
	self.context:SetBlendMode(Blend.Alpha)
	if DEBUG then
		self.context:SetColor(1,0,0,1)
		self.context:DrawText("Debug Mode",2,2)
		self.context:SetColor(1,1,1,1)
		self.context:DrawStats(2,22)
		self.context:SetBlendMode(Blend.Solid)
	else
		self.context:SetColor(1,1,1,1)
		self.context:DrawText("FPS: "..Math:Round(Time:UPS()),2,2)
	end
	
	--Refresh the screen
	self.context:Sync(false)
	
	--Returning true tells the main program to keep looping
	return true
end
