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
local ClientEffects = require(script.ClientEffects)
local CameraController = require(script.Parent.CameraController)
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

-- TODO: Temp testing states for promotion
local isPromoting = false
local PromotionContainer: Model

local function initMenuScreen()
	-- Set up camera
	CameraController.camFocus = MENU_CAM_POS + Vector3.zAxis * 50
	CameraController.camPos = MENU_CAM_POS

	-- Set up menu pieces
	local PawnModel = ClientEffects.createPieceModel("Pawn", "White", "NA")
	local Pawn = PawnModel.PrimaryPart :: BasePart
	PawnModel.Parent = MenuObjects
	PawnModel:ScaleTo(0.5 / ClientEffects.PIECE_SCALE_FACTOR)
	ClientEffects.floatPiece(PawnModel, CFrame.new(CameraController.camFocus))

	-- Create billboard label
	local LabelGUI = ReplicatedStorage.Assets.UI.MenuPieceLabel:Clone()
	LabelGUI.Size = UDim2.fromScale(Pawn.Size.Y * 4, Pawn.Size.Y * 2)
	LabelGUI.StudsOffset = Vector3.new(0, Pawn.Size.Y / 2 * 1.25, 0)
	LabelGUI.Parent = Player.PlayerGui
	LabelGUI.Adornee = Pawn

	local Frame = LabelGUI.CanvasGroup.Frame
	local textObject
	task.delay(0.15, function()
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
	PieceModels = {}
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

-- Helper function to place piece at mouse cf relative to board
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

local HOVER_FLOAT_TIME_S = 0.1
local function unhoverPiece()
	if not HoveredPieceModel or not HoveredPieceModel:FindFirstChild("Display") then return end
	local Display = HoveredPieceModel:FindFirstChild("Display") :: BasePart

	PieceHighlight:Destroy()
	hideMoveHighlights()
	TweenService
		:Create(
			Display,
			TweenInfo.new(HOVER_FLOAT_TIME_S),
			{ CFrame = HoveredPieceModel.WorldPivot }
		)
		:Play()

	HoveredPieceModel = nil
end

-- Piece dragging
local PIECE_ROT_LIMIT_RAD = math.pi / 3
local prevSelectedPiecePos = Vector3.zero
local rotSpring = Spring.new(Vector2.zero)
local posSpring = Spring.new(Vector3.zero)
local sizeSpring = Spring.new(Vector3.zero)
rotSpring.Damper = 0.4
rotSpring.Speed = 20
posSpring.Damper = 1
posSpring.Speed = 30
sizeSpring.Damper = 0.25
sizeSpring.Speed = 25
local tweenedVel = Vector3.zero -- intermediary value required for lerp

RunService.Heartbeat:Connect(function(dt: number)
	if not SelectedPieceModel then return end
	local DisplayPart = SelectedPieceModel:FindFirstChild("Display") :: BasePart

	-- Handle promotion UI piece selection
	if isPromoting then
		DisplayPart.Size = sizeSpring.Position
		return
	end

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

local function placePiece(targetCoord: Vector2, SelectedPieceModel: Model): boolean
	local pieceUID = SelectedPieceModel:GetAttribute("UID") :: string
	local selectedPiece = ChessUtils.getPieceFromUID(pieceUID, currentChessGame.state)
	if
		not selectedPiece
		or not ChessUtils.isMoveValid(selectedPiece, targetCoord, currentChessGame.state)
	then
		return false
	end
	GameServiceRemote:FireServer("PlacePiece", targetCoord, SelectedPieceModel:GetAttribute("UID"))
	return true
end

Mouse.Button1Down:Connect(function()
	if currentChessGame and playerColor ~= currentChessGame.turn or not HoveredPieceModel then
		return
	end
	SelectedPieceModel = HoveredPieceModel
	selectedPieceTargetCF = getSelectedPieceMouseCF(HoveredPieceModel)
	prevSelectedPiecePos = selectedPieceTargetCF.Position
	posSpring.Position = prevSelectedPiecePos
	rotSpring.Position = Vector2.zero
end)

Mouse.Button1Up:Connect(function()
	if not currentChessGame then return end

	-- Promotion selection
	if isPromoting and SelectedPieceModel then
		GameServiceRemote:FireServer("PromotePiece", SelectedPieceModel.Name)
		isPromoting = false
		local offsetDelay = HOVER_FLOAT_TIME_S / 4
		task.defer(function()
			for _, PieceModel in pairs(PromotionContainer:GetChildren()) do
				local Display = PieceModel:FindFirstChild("Display") :: BasePart
				TweenService
					:Create(Display, TweenInfo.new(HOVER_FLOAT_TIME_S), { Size = Vector3.zero })
					:Play()
				task.wait(offsetDelay)
			end
			local numPieces = #PromotionContainer:GetChildren()
			task.delay(
				(HOVER_FLOAT_TIME_S + offsetDelay) * numPieces,
				function() PromotionContainer:Destroy() end
			)
		end)
	end

	if
		not SelectedPieceModel
		or not ChessUtils.isCoordValid(mouseBoardCoord, currentChessGame.state)
	then
		return
	end
	local DisplayPart = SelectedPieceModel:FindFirstChild("Display") :: BasePart

	-- Try to place piece
	local isCapture = not ChessUtils.isCoordEmpty(mouseBoardCoord, currentChessGame.state)
	if placePiece(mouseBoardCoord, SelectedPieceModel) then
		hideMoveHighlights()
		ReplicatedStorage.Assets.Sounds[isCapture and "Take" or "Move"]:Play()
		return
	end

	-- Invalid placement, replace part to start
	DisplayPart.CFrame = SelectedPieceModel.WorldPivot
	SelectedPieceModel = nil
	ReplicatedStorage.Assets.Sounds.Hover:Play()
end)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include

UserInputService.InputChanged:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

	-- Handle promotion selection
	if isPromoting then
		local function shrinkPieceModelDisplay(PieceModel: Model)
			local Display = PieceModel:FindFirstChild("Display") :: BasePart
			TweenService:Create(
				Display,
				TweenInfo.new(HOVER_FLOAT_TIME_S),
				{ Size = Display:GetAttribute("OrigSize") :: Vector3 }
			):Play()
		end
		if
			Mouse.Target
			and Mouse.Target.Parent
			and Mouse.Target:IsDescendantOf(PromotionContainer)
		then
			local PieceModel = Mouse.Target.Parent
			if HoveredPieceModel == PieceModel then return end

			PieceHighlight:Destroy()
			HoveredPieceModel = PieceModel
			SelectedPieceModel = PieceModel
			local PiecePart = Mouse.Target.Parent:FindFirstChild("Display")
			PieceHighlight = ClientEffects.highlightPiece(PiecePart)

			local origSize = PiecePart:GetAttribute("OrigSize") :: Vector3
			sizeSpring.Position = PiecePart.Size
			sizeSpring.Target = origSize * 2

			-- ReplicatedStorage.Assets.Sounds.Hover:Play()
			ReplicatedStorage.Assets.Sounds.Bubble:Play()

			for _, Model in pairs(PromotionContainer:GetChildren()) do
				if Model == PieceModel or not Model:IsA("Model") then continue end
				shrinkPieceModelDisplay(Model)
			end

			return
		end

		SelectedPieceModel = nil
		PieceHighlight:Destroy()
		if HoveredPieceModel then shrinkPieceModelDisplay(HoveredPieceModel) end
		HoveredPieceModel = nil
		return
	end

	--TODO: temp way to ignore menu UI pieces
	if Mouse.Target and Mouse.Target.Parent and Mouse.Target.Parent:GetAttribute("UID") == "NA" then
		return
	end

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
		for coordString, Highlight in pairs(ActiveMoveHighlights) do
			Highlight.FillColor = coordString == tostring(mouseBoardCoord)
					and ChessTypes.hoverHighlightColors.pieceMoveSquareColor
				or ChessTypes.hoverHighlightColors.selectColor
		end
		return
	end

	-- Check mouse hit is valid
	if not Mouse.Target then
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
	if not hoveringPiece or ((hoveringPiece.Color ~= playerColor) and true) then -- TODO: temp test
		unhoverPiece()
		return
	end

	-- Unhover currently hovered piece if applicable
	unhoverPiece()

	-- Apply hover effect to newly hovered piece
	local PiecePart = PieceModel:FindFirstChild("Display")
	if not PiecePart then return end
	PieceHighlight = ClientEffects.highlightPiece(PieceModel)
	HoveredPieceModel = PieceModel
	TweenService:Create(PiecePart, TweenInfo.new(HOVER_FLOAT_TIME_S), {
		CFrame = PieceModel.WorldPivot * CFrame.new(0, DefaultSquare.Size.Y / 2, 0),
		-- Size =
	}):Play()

	-- Highlight moves
	highlightMoves(hoveringPiece :: ChessTypes.Piece, currentChessGame.state, BoardModel)

	-- Play sound
	ReplicatedStorage.Assets.Sounds.Hover:Play()
end)

local function setupGame(chessGame: ChessTypes.ChessGame)
	-- Hide menu objects
	MenuObjects.Parent = Lighting

	-- Create board
	local Board = ClientEffects.buildBoard()
	BoardModel = Board
	for _, RankModel in pairs(BoardModel:GetChildren()) do
		if not RankModel:IsA("Model") then continue end
		for _, Square in pairs(RankModel:GetChildren()) do
			params:AddToFilter(Square)
		end
	end

	-- Set board CFrame and camera focus
	local ReferenceGUI = ReplicatedStorage.Assets.UI.ReferenceGUI
	ReferenceGUI.Parent = Player.PlayerGui
	local projectedCF =
		CameraController.fitPartToFrame(Board.PrimaryPart :: Part, ReferenceGUI.BoardArea)
	local dist = (Camera.CFrame.Position - projectedCF.Position).Magnitude
	local boardCF = CFrame.new(MENU_CAM_POS)
		* CFrame.new(
			0, -- -dist * math.sin(ClientEffects.ANG_FROM_VERT_RAD),
			-dist * math.cos(ClientEffects.ANG_FROM_VERT_RAD),
			dist * math.sin(ClientEffects.ANG_FROM_VERT_RAD)
		)
	Board:PivotTo(boardCF)

	CameraController.camFocus = boardCF.Position

	-- Populate initial board pieces from given state
	updateGame(chessGame)

	-- Set player color
	playerColor = (chessGame.WhitePlayer == Player and "White" or "Black") :: ChessTypes.PieceColor
end

function updateGame(updateChessGame: ChessTypes.ChessGame)
	currentChessGame = updateChessGame
	clearPieces()
	PieceModels = ClientEffects.populatePieces(BoardModel, currentChessGame.state)
end

function ChessController.init(RuntimeFolder: Folder, RemotesFolder: Folder)
	GameServiceRemote = RemotesFolder:FindFirstChild("GameServiceRemote", true) :: RemoteEvent

	local function handlePromotion(targetCoord: Vector2, pieceUID: string)
		PromotionContainer = ClientEffects.promptPromotion(
			ChessUtils.getPieceFromUID(pieceUID, currentChessGame.state) :: ChessTypes.Piece,
			targetCoord
		)
		isPromoting = true
	end

	GameServiceRemote.OnClientEvent:Connect(function(eventName: string, ...)
		if eventName == "StartGame" then
			setupGame(...)
		elseif eventName == "UpdateGame" then
			updateGame(...)
		elseif eventName == "PromptPromotion" then
			handlePromotion(...)
		end
	end)
end

function ChessController.start()
	-- Freeze character
	local Char = Player.Character or Player.CharacterAdded:Wait()
	local RootPart = Char:WaitForChild("HumanoidRootPart")
	RootPart.Anchored = true

	-- Init menu
	initMenuScreen()

	CameraController.changeState("Menu")
end

return ChessController
