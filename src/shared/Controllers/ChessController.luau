--!strict

local MENU_CAM_POS = Vector3.new(0, 0, 0)

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ChessController = {}

local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

local GameServiceRemote: RemoteEvent
local MenuObjects = Instance.new("Model", workspace)

local globalTargCamPos = Vector3.new()

local function initMenuScreen()
	-- Set up camera
	local camFocus = MENU_CAM_POS + Vector3.zAxis * 100
	Camera.FieldOfView = 15
	Camera.CameraType = Enum.CameraType.Scriptable
	globalTargCamPos = camFocus

	-- Set up menu pieces
	local Pawn = ReplicatedStorage.Assets.Pieces.Pawn:Clone()
	Pawn.Anchored = true
	Pawn.Parent = MenuObjects
	Pawn.CFrame = CFrame.new(camFocus)
	Pawn.Size = Pawn.Size * 2 / 5

	-- Create billboard label
	local LabelGUI = ReplicatedStorage.Assets.UI.MenuPieceLabel:Clone()
	LabelGUI.Size = UDim2.fromScale(Pawn.Size.Y * 2, Pawn.Size.Y)
	LabelGUI.Parent = Player.PlayerGui
	LabelGUI.Adornee = Pawn

	-- Set up click detector
	local Detector = Instance.new("ClickDetector", Pawn)
	Detector.MaxActivationDistance = math.huge
	Detector.MouseClick:Connect(function() GameServiceRemote:FireServer("RequestGame") end)
end

local function populatePieces(stateFEN: string)
	local rank, file = 8, 1
	for i = 1, #stateFEN do
		local c = stateFEN:sub(i, i)
	end
end

local function buildBoard()
	local Board = Instance.new("Model", workspace)
	local DefaultSquare = ReplicatedStorage.Assets.Board.DefaultSquare

	-- Create root part for centering board
	local d = DefaultSquare.Size.X
	local RootPart = Instance.new("Part", Board)
	RootPart.Name = "Root"
	RootPart.Size = Vector3.new(d * 8, d, d * 8)
	RootPart.Transparency = 1
	RootPart.Anchored = true
	RootPart.CanCollide = false
	Board.PrimaryPart = RootPart

	-- Create board
	for rank = 1, 8 do
		for file = 1, 8 do
			local Square = DefaultSquare:Clone()
			Square.CFrame = RootPart.CFrame * CFrame.new((file - 4) * d, 0, (rank - 4) * d)
			Square.BrickColor = (rank + file) % 2 == 0 and BrickColor.White() or BrickColor.Black()
			Square.Parent = Board
		end
	end

	return Board
end

local function setupGame()
	-- Hide menu objects
	MenuObjects.Parent = Lighting

	-- Create board
	local Board = buildBoard()

	-- Change camera
	local fitPartToFrame = function(Part: BasePart, Frame: Frame): CFrame
		local topBarOffset = GuiService.TopbarInset.Height
		local framePosX = Frame.AbsolutePosition.X + Frame.AbsoluteSize.X / 2
		local framePosY = (Frame.AbsolutePosition.Y + topBarOffset) + Frame.AbsoluteSize.Y / 2

		local zBaseOffset = Part.Size.X
			/ (
				2
				* math.tan(math.rad(Camera.FieldOfView) / 2)
				* (Frame.AbsoluteSize.Y / Camera.ViewportSize.Y)
			)

		local unitRay = Camera:ViewportPointToRay(framePosX, framePosY, zBaseOffset)

		unitRay = Camera:ViewportPointToRay(
			framePosX,
			framePosY,
			zBaseOffset / math.cos(unitRay.Direction:Angle(Camera.CFrame.LookVector))
		)

		-- Apply and fix CFrame towards camera
		local baseCF = CFrame.new(unitRay.Origin)
		local x, y, z = Camera.CFrame:ToEulerAnglesXYZ()
		baseCF *= CFrame.Angles(x, y, z)
		baseCF *= CFrame.Angles(0, math.pi, 0) -- Flip part around so front faces camera

		return baseCF
	end

	local ReferenceGUI = ReplicatedStorage.Assets.UI.ReferenceGUI
	ReferenceGUI.Parent = Player.PlayerGui
	local projectedCF = fitPartToFrame(Board.PrimaryPart :: Part, ReferenceGUI.BoardArea)
	local dist = (Camera.CFrame.Position - projectedCF.Position).Magnitude

	local ANG_FROM_VERT_RAD = math.rad(30)
	local boardCF = CFrame.new(MENU_CAM_POS)
		* CFrame.new(0, -dist * math.cos(ANG_FROM_VERT_RAD), dist * math.sin(ANG_FROM_VERT_RAD))
	Board:PivotTo(boardCF)

	globalTargCamPos = boardCF.Position
end

function ChessController.init(RuntimeFolder: Folder, RemotesFolder: Folder)
	GameServiceRemote = RemotesFolder:FindFirstChild("GameServiceRemote", true) :: RemoteEvent

	GameServiceRemote.OnClientEvent:Connect(function(eventName: string)
		if eventName == "StartGame" then setupGame() end
	end)
end

function ChessController.start()
	-- Freeze character
	local Char = Player.Character or Player.CharacterAdded:Wait()
	local RootPart = Char:WaitForChild("HumanoidRootPart")
	RootPart.Anchored = true

	-- Init menu
	initMenuScreen()

	-- Camera loop
	local screenSize = Camera.ViewportSize
	local screenCenter = screenSize / 2
	RunService.Heartbeat:Connect(function()
		local camFocusDist = (MENU_CAM_POS - globalTargCamPos).Magnitude
		local mouseDriftMag = camFocusDist * 0.01
		local mousePos = UserInputService:GetMouseLocation() - screenCenter
		local mouseOffsetCF = CFrame.new(
			mousePos.X / screenSize.X * mouseDriftMag,
			-mousePos.Y / screenSize.Y * mouseDriftMag,
			0
		)
		local targCamCF = CFrame.lookAt(MENU_CAM_POS, globalTargCamPos) * mouseOffsetCF
		Camera.CFrame = Camera.CFrame:Lerp(targCamCF, 0.1)
	end)
end

return ChessController
