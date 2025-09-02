--!strict

local MENU_CAM_POS = Vector3.new(0, 0, 0)

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ChessUtils = require(ReplicatedStorage.Modules.Libraries.ChessUtils)
local RichText = require(ReplicatedStorage.Modules.Libraries.RichText)
local Spring = require(ReplicatedStorage.Modules.Libraries.Spring)
local ChessTypes = require(ReplicatedStorage.Modules.Types.ChessTypes)

local ChessController = {}

local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

local GameServiceRemote: RemoteEvent
local MenuObjects = Instance.new("Model", workspace)

local DefaultSquare = ReplicatedStorage.Assets.Board.DefaultSquare

-- Current client game vars
local globalTargCamPos = Vector3.new()

local PieceModels: { [string]: Model } = {}
local playerColor: ChessTypes.PieceColor = "White" -- Default, gets set when game starts
local PieceHighlight: Highlight
local ActiveMoveHighlights: { [string]: Highlight } = {}
local BoardModel: Model
local currentChessGame: ChessTypes.ChessGame

local function initMenuScreen()
	-- Set up camera
	local camFocus = MENU_CAM_POS + Vector3.zAxis * 50
	Camera.FieldOfView = 15
	Camera.CameraType = Enum.CameraType.Scriptable
	globalTargCamPos = camFocus
	Camera.CFrame = CFrame.lookAt(MENU_CAM_POS, globalTargCamPos)

	-- Set up menu pieces
	local Pawn = ReplicatedStorage.Assets.Pieces.Pawn:Clone()
	Pawn.Anchored = true
	Pawn.Parent = MenuObjects
	local PIECE_SPAWN_ANG_RAD = math.rad(30)
	local PIECE_FLOAT_ANG_SCALE = 1
	Pawn.CFrame = CFrame.new(camFocus)
		* CFrame.Angles(
			-PIECE_SPAWN_ANG_RAD / 2 + math.random() * PIECE_SPAWN_ANG_RAD,
			-PIECE_SPAWN_ANG_RAD / 2 + math.random() * PIECE_SPAWN_ANG_RAD,
			-PIECE_SPAWN_ANG_RAD / 2 + math.random() * PIECE_SPAWN_ANG_RAD
		)
	Pawn.Size = Pawn.Size * 2 / Pawn.Size.Y

	-- Animate menu pieces
	local origCF = Pawn.CFrame
	local t = 0
	RunService.Heartbeat:Connect(function(dt: number)
		Pawn.CFrame = origCF
			* CFrame.new(0, math.sin(tick() * 2) / 4, 0)
			* CFrame.Angles(
				math.noise(1, t) * PIECE_FLOAT_ANG_SCALE,
				math.noise(2, t) * PIECE_FLOAT_ANG_SCALE,
				math.noise(3, t) * PIECE_FLOAT_ANG_SCALE
			)
		t += dt / 4
	end)

	-- Create billboard label
	local LabelGUI = ReplicatedStorage.Assets.UI.MenuPieceLabel:Clone()
	LabelGUI.Size = UDim2.fromScale(Pawn.Size.Y * 4, Pawn.Size.Y * 2)
	LabelGUI.StudsOffset = Vector3.new(0, Pawn.Size.Y / 2 * 1.25, 0)
	LabelGUI.Parent = Player.PlayerGui
	LabelGUI.Adornee = Pawn

	local Frame = LabelGUI.CanvasGroup.Frame
	local textObject
	task.delay(0.1, function()
		local text = "play!"
		textObject = RichText:New(Frame, text, {
			Looping = true,
			AnimateStyle = "Float",
			AnimateStyleTime = 4,
			AnimateStyleAmplitude = 0.1,
			Font = Enum.Font.DenkOne,
			TextStrokeTransparency = 0,
			BorderSizePixel = 3,
			TextScale = 1,
			ContainerHorizontalAlignment = "Center",
		})
		textObject:Animate(false)
	end)

	-- Set up click detector
	local origFrameSize = LabelGUI.CanvasGroup.Size
	local Detector = Instance.new("ClickDetector", Pawn)
	Detector.MaxActivationDistance = math.huge
	Detector.MouseClick:Connect(function() GameServiceRemote:FireServer("RequestGame") end)
	local incScale = 0.5
	local TWEEN_TIME = 0.25
	Detector.MouseHoverEnter:Connect(function()
		TweenService:Create(
			LabelGUI.CanvasGroup,
			TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Size = origFrameSize + UDim2.fromScale(incScale, incScale),
			}
		):Play()
		for _, Label in pairs(LabelGUI:GetDescendants()) do
			if not Label:IsA("TextLabel") or not Label.Name:find("Char") then continue end
			TweenService:Create(Label, TweenInfo.new(TWEEN_TIME), {
				TextColor3 = ChessTypes.menuColors.playAIColor,
			}):Play()
		end
		textObject:animateChars()
	end)
	Detector.MouseHoverLeave:Connect(function()
		TweenService:Create(
			LabelGUI.CanvasGroup,
			TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Size = origFrameSize,
			}
		):Play()
		for _, Label in pairs(LabelGUI:GetDescendants()) do
			if not Label:IsA("TextLabel") or not Label.Name:find("Char") then continue end
			TweenService:Create(Label, TweenInfo.new(TWEEN_TIME), {
				TextColor3 = Color3.fromRGB(255, 255, 255),
			}):Play()
		end
	end)
end

-- Calculate scale of pieces relative to board
local PIECE_FULLNESS = 0.75
local PIECE_SCALE_FACTOR = 1
do
	local d = DefaultSquare.Size.X
	local largest = 0
	for _, Piece in pairs(ReplicatedStorage.Assets.Pieces:GetChildren()) do
		if not Piece:IsA("BasePart") then continue end
		if Piece.Size.X > largest then largest = Piece.Size.X end
	end
	PIECE_SCALE_FACTOR = d / largest * PIECE_FULLNESS
end

local function populatePieces(Board: Model, boardState: ChessTypes.BoardState)
	local BoardRoot = Board.PrimaryPart :: BasePart
	local squareSize = (BoardRoot.Size / 8).X
	local boardOrigin = BoardRoot.CFrame
	for rank, rankTab in ipairs(boardState) do
		for file, piece in ipairs(rankTab) do
			local PiecePart: BasePart? = ReplicatedStorage.Assets.Pieces:FindFirstChild(piece.Type)
			if not PiecePart then continue end
			PiecePart = PiecePart:Clone()
			PiecePart.Color = ChessTypes.colors[piece.Color]
			PiecePart.Size *= PIECE_SCALE_FACTOR
			PiecePart.Name = "Display"

			local PieceModel = Instance.new("Model", workspace)
			local PieceHitbox = Instance.new("Part", PieceModel)
			PieceHitbox.Size = (BoardRoot.Size / 8) * 0.85
			PieceHitbox.Transparency = 0.85
			PieceHitbox.Anchored = true
			PieceHitbox.CanCollide = false
			PiecePart.Parent = PieceModel
			PieceModel.PrimaryPart = PieceHitbox
			PieceModel:SetAttribute("UID", piece.UID)
			PieceModel.Name = piece.Type
			PieceModel:PivotTo(
				boardOrigin
					* CFrame.new(
						squareSize * 4.5 - file * squareSize,
						squareSize / 2 + PiecePart.Size.Y / 2,
						rank * squareSize - squareSize * 4.5
					)
			)
			PiecePart.CFrame = PieceModel.WorldPivot
			PieceModels[piece.UID] = PieceModel
		end
	end
end

--[[
	Mouse enter / leave player piece
]]

local SelectedPieceModel: Model?
local selectedPieceTargetCF: CFrame = CFrame.new()
local HoveredPieceModel: Model?
local mouseBoardCoord: Vector2

local function clearPieces()
	HoveredPieceModel = nil
	SelectedPieceModel = nil
	for _, PieceModel in pairs(PieceModels) do
		PieceModel:Destroy()
	end
end

local function hideMoveHighlights()
	for _, Obj in pairs(ActiveMoveHighlights) do
		Obj:Destroy()
	end
	ActiveMoveHighlights = {}
end

local function highlightMoves(
	piece: ChessTypes.Piece,
	boardState: ChessTypes.BoardState,
	Board: Model
)
	-- Reset old highlights
	hideMoveHighlights()
	local validCoords = ChessUtils.getValidMoves(piece, boardState)

	-- Create highlights and (Tile effect?)
	local HIGHLIGHT_TILE_TIME_S = 0.1
	task.spawn(function()
		for _, coord in pairs(validCoords) do
			local Square = ChessUtils.getBoardSquareFromCoord(coord, Board)
			local Highlight = Instance.new("Highlight", Square)
			Highlight.Adornee = Square
			Highlight.FillColor = ChessTypes.hoverHighlightColors.selectColor
			Highlight.FillTransparency = 0.5
			Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			ActiveMoveHighlights[tostring(coord)] = Highlight
		end
		-- for _, HighlightSquare in ipairs(ActiveMoveHighlights) do
		-- 	TweenService:Create(
		-- 		HighlightSquare,
		-- 		TweenInfo.new(HIGHLIGHT_TILE_TIME_S),
		-- 		{ Size = origSize, Transparency = 0.25 }
		-- 	):Play()
		-- 	task.wait(HIGHLIGHT_TILE_TIME_S / 5)
		-- end
	end)
end

local HOVER_FLOAT_TIME_S = 0.1
local function getSelectedPieceMouseCF(PieceModel: Model)
	local camPos = Camera.CFrame.Position
	local hoverRootPos = BoardModel.WorldPivot + Vector3.new(0, DefaultSquare.Size.Y * 3.5)
	local dist = math.abs(camPos.Y - hoverRootPos.Y)
	local camToMouseDir = (camPos - Mouse.Hit.Position).Unit
	local ang = math.acos(-Vector3.yAxis:Dot(camToMouseDir))

	local DisplayPart = PieceModel:FindFirstChild("Display") :: BasePart
	return CFrame.new(
		CFrame.lookAt(camPos, Mouse.Hit.Position) * CFrame.new(0, 0, dist * math.cos(ang)).Position
	) * CFrame.new(0, -DisplayPart.Size.Y / 2, 0)
end

local function unhoverPiece()
	if not HoveredPieceModel or not HoveredPieceModel:FindFirstChild("Display") then return end
	PieceHighlight:Destroy()
	TweenService:Create(
		HoveredPieceModel:FindFirstChild("Display"),
		TweenInfo.new(HOVER_FLOAT_TIME_S),
		{ CFrame = HoveredPieceModel.WorldPivot }
	):Play()
	HoveredPieceModel = nil
	hideMoveHighlights()
end

-- Piece dragging
local PIECE_ROT_LIMIT_RAD = math.pi / 3
local prevSelectedPiecePos = Vector3.zero
local rotSpring = Spring.new(Vector2.zero)
local posSpring = Spring.new(Vector3.zero)
rotSpring.Damper = 0.5
rotSpring.Speed = 20
posSpring.Damper = 1
posSpring.Speed = 30
local tweenedVel = Vector3.zero -- intermediary value required for lerp

RunService.Heartbeat:Connect(function(dt: number)
	if not SelectedPieceModel then return end
	local DisplayPart = SelectedPieceModel:FindFirstChild("Display") :: BasePart

	-- Update vel from mouse movement
	local offsetCF = CFrame.new(0, DisplayPart.Size.Y / 2, 0)
	local vel = (selectedPieceTargetCF.Position - prevSelectedPiecePos) / dt * 0.05
	tweenedVel = tweenedVel + (vel - tweenedVel) * (1 - math.exp(-rotSpring.Speed * 20 * dt))

	-- Update springs and apply CF
	rotSpring:SetTarget(Vector2.new(tweenedVel.X, tweenedVel.Z))
	posSpring:SetTarget(selectedPieceTargetCF.Position)

	DisplayPart.CFrame = CFrame.new(posSpring.Position)
		* offsetCF
		* CFrame.Angles(
			math.clamp(rotSpring.Position.Y, -PIECE_ROT_LIMIT_RAD, PIECE_ROT_LIMIT_RAD),
			0,
			-math.clamp(rotSpring.Position.X, -PIECE_ROT_LIMIT_RAD, PIECE_ROT_LIMIT_RAD)
		)
		* offsetCF:Inverse()

	-- Update prev pos
	prevSelectedPiecePos = selectedPieceTargetCF.Position
end)

Mouse.Button1Down:Connect(function()
	if not HoveredPieceModel then return end
	SelectedPieceModel = HoveredPieceModel
	selectedPieceTargetCF = getSelectedPieceMouseCF(HoveredPieceModel)
	prevSelectedPiecePos = selectedPieceTargetCF.Position
	posSpring.Position = prevSelectedPiecePos
	rotSpring.Position = Vector2.zero
end)

local function placePiece(targetCoord: Vector2, SelectedPieceModel: Model): boolean
	if not ActiveMoveHighlights[tostring(targetCoord)] then return false end
	GameServiceRemote:FireServer("PlacePiece", targetCoord, SelectedPieceModel:GetAttribute("UID"))
	return true
end

Mouse.Button1Up:Connect(function()
	if not SelectedPieceModel then return end
	local DisplayPart = SelectedPieceModel:FindFirstChild("Display") :: BasePart

	-- Try to place part
	if placePiece(mouseBoardCoord, SelectedPieceModel) then return end

	-- Invalid placement, replace part to start
	DisplayPart.CFrame = SelectedPieceModel.WorldPivot
	SelectedPieceModel = nil
end)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

UserInputService.InputChanged:Connect(function(input: InputObject)
	-- Update which board square coord is mouse in
	local mouseHitPos = Mouse.Hit.Position
	local camPos = Camera.CFrame.Position
	local camToMouseDir = (mouseHitPos - camPos).Unit
	local ray = Workspace:Raycast(camPos, camToMouseDir * 9999, params)
	if ray and ray.Instance and ray.Instance.Parent then
		mouseBoardCoord =
			Vector2.new(tonumber(ray.Instance.Parent.Name), tonumber(ray.Instance.Name))
	else
		mouseBoardCoord = Vector2.zero
	end

	-- State for when piece is already being dragged, skip piece hover checks
	if SelectedPieceModel and Mouse.Hit then
		selectedPieceTargetCF = getSelectedPieceMouseCF(SelectedPieceModel)
		return
	end

	-- Check mouse hit is valid
	if input.UserInputType ~= Enum.UserInputType.MouseMovement or not Mouse.Target then
		unhoverPiece()
		return
	end

	-- Check if mouse is hovering over a piece
	local PieceModel = Mouse.Target.Parent
	if not PieceModel or not PieceModel:GetAttribute("UID") then
		unhoverPiece()
		return
	end

	-- Do nothing if hovering over same piece
	if HoveredPieceModel == PieceModel then return end

	-- Check mouse is hovering over player's piece
	local hoveringPiece = ChessUtils.getPieceFromModel(PieceModel, currentChessGame.state)
	if not hoveringPiece or hoveringPiece.Color ~= playerColor then
		unhoverPiece()
		return
	end

	-- Unhover currently hovered piece if applicable
	unhoverPiece()

	-- Apply hover effect to newly hovered piece
	local PiecePart = PieceModel:FindFirstChild("Display")
	if not PiecePart then return end
	HoveredPieceModel = PieceModel
	PieceHighlight = Instance.new("Highlight")
	PieceHighlight.Adornee = PiecePart
	TweenService:Create(
		PiecePart,
		TweenInfo.new(HOVER_FLOAT_TIME_S),
		{ CFrame = PieceModel.WorldPivot * CFrame.new(0, DefaultSquare.Size.Y / 2, 0) }
	):Play()

	-- Apply highlight effect to newly hovered piece
	PieceHighlight.Parent = PiecePart
	PieceHighlight.Adornee = PiecePart
	PieceHighlight.Enabled = true
	PieceHighlight.FillTransparency = 0.5
	PieceHighlight.FillColor = ChessTypes.hoverHighlightColors.selectColor
	TweenService:Create(
		PieceHighlight,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.75 }
	):Play()

	-- Highlight moves
	highlightMoves(hoveringPiece :: ChessTypes.Piece, currentChessGame.state, BoardModel)

	-- Play sound
	ReplicatedStorage.Assets.Sounds.Hover:Play()
end)

local function buildBoard()
	local Board = Instance.new("Model", workspace)
	Board.Name = "Board"

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
		local RankModel = Instance.new("Model", Board)
		RankModel.Name = tostring(rank)
		for file = 1, 8 do
			local Square = DefaultSquare:Clone()
			Square.CFrame = RootPart.CFrame * CFrame.new(d * 4.5 - file * d, 0, rank * d - d * 4.5)
			Square.BrickColor = (rank + file) % 2 == 0 and BrickColor.Black() or BrickColor.White()
			Square.Parent = RankModel
			Square.Name = tostring(file)
		end
	end

	return Board
end

local function setupGame(chessGame: ChessTypes.ChessGame)
	-- Hide menu objects
	MenuObjects.Parent = Lighting

	-- Create board
	local Board = buildBoard()
	BoardModel = Board
	for _, RankModel in pairs(BoardModel:GetChildren()) do
		if not RankModel:IsA("Model") then continue end
		for _, Square in pairs(RankModel:GetChildren()) do
			params:AddToFilter(Square)
		end
	end

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

	local ANG_FROM_VERT_RAD = math.rad(25)
	local boardCF = CFrame.new(MENU_CAM_POS)
		* CFrame.new(
			0, -- -dist * math.sin(ANG_FROM_VERT_RAD),
			-dist * math.cos(ANG_FROM_VERT_RAD),
			dist * math.sin(ANG_FROM_VERT_RAD)
		)
	Board:PivotTo(boardCF)

	globalTargCamPos = boardCF.Position

	-- Populate initial board pieces from given state
	populatePieces(Board, chessGame.state)

	-- Set player color
	playerColor = (chessGame.WhitePlayer == Player and "White" or "Black") :: ChessTypes.PieceColor

	currentChessGame = chessGame
end

function updateGame(updateChessGame: ChessTypes.ChessGame)
	currentChessGame = updateChessGame
	clearPieces()
	populatePieces(BoardModel, currentChessGame.state)
end

function ChessController.init(RuntimeFolder: Folder, RemotesFolder: Folder)
	GameServiceRemote = RemotesFolder:FindFirstChild("GameServiceRemote", true) :: RemoteEvent

	GameServiceRemote.OnClientEvent:Connect(function(eventName: string, ...)
		if eventName == "StartGame" then
			setupGame(...)
		elseif eventName == "UpdateGame" then
			updateGame(...)
		end
	end)
end

local CAMERA_PAN_FACTOR = 16
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
	RunService.Heartbeat:Connect(function(dt: number)
		local camFocusDist = (MENU_CAM_POS - globalTargCamPos).Magnitude
		local mouseDriftMag = camFocusDist * 0.0075
		local mousePos = UserInputService:GetMouseLocation() - screenCenter
		local mouseOffsetCF = CFrame.new(
			mousePos.X / screenSize.X * mouseDriftMag,
			-mousePos.Y / screenSize.Y * mouseDriftMag,
			0
		)
		local targCamCF = CFrame.lookAt(MENU_CAM_POS, globalTargCamPos) * mouseOffsetCF
		Camera.CFrame = Camera.CFrame:Lerp(targCamCF, 1 - math.exp(-CAMERA_PAN_FACTOR * dt))
	end)
end

return ChessController
