--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local ChessUtils = require(ReplicatedStorage.Modules.Libraries.ChessUtils)
local RichText = require(ReplicatedStorage.Modules.Libraries.RichText)
local ChessTypes = require(ReplicatedStorage.Modules.Types.ChessTypes)

-- TODO: redundant reference
local DefaultSquare = ReplicatedStorage.Assets.Board.DefaultSquare

local ClientEffects = {}

local BoardModel: Model

-- Camera board view ang from vertical
ClientEffects.ANG_FROM_VERT_RAD = math.rad(25)

-- Calculate scale of pieces relative to board
local PIECE_FULLNESS = 0.75
ClientEffects.PIECE_SCALE_FACTOR = 1
do
	local d = DefaultSquare.Size.X
	local largest = 0
	for _, Piece in pairs(ReplicatedStorage.Assets.Pieces:GetChildren()) do
		if not Piece:IsA("BasePart") then continue end
		if Piece.Size.X > largest then largest = Piece.Size.X end
	end
	ClientEffects.PIECE_SCALE_FACTOR = d / largest * PIECE_FULLNESS
end

function ClientEffects.buildBoard()
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
			local squareColor: ChessTypes.PieceColor = (
				(rank + file) % 2 == 0 and "White" or "Black"
			) :: ChessTypes.PieceColor
			Square.CFrame = RootPart.CFrame * CFrame.new(d * 4.5 - file * d, 0, rank * d - d * 4.5)
			Square.Color = ChessTypes.boardColors[squareColor]
			Square.Parent = RankModel
			Square.Name = tostring(file)
		end
	end

	BoardModel = Board -- TODO: dependency injection or something?
	return Board
end

function ClientEffects.floatPiece(
	PieceModel: Model,
	originCF: CFrame,
	randAngDeg: number?,
	delay: number?
)
	local PIECE_SPAWN_ANG_RAD = math.rad(randAngDeg or 30)
	local PIECE_FLOAT_ANG_SCALE = math.rad(randAngDeg and randAngDeg * 2 or 45)
	PieceModel:PivotTo(
		originCF
			* CFrame.Angles(
				-PIECE_SPAWN_ANG_RAD / 2 + math.random() * PIECE_SPAWN_ANG_RAD,
				-PIECE_SPAWN_ANG_RAD / 2 + math.random() * PIECE_SPAWN_ANG_RAD,
				-PIECE_SPAWN_ANG_RAD / 2 + math.random() * PIECE_SPAWN_ANG_RAD
			)
	)

	local startCF = PieceModel.WorldPivot
	local t = 0
	local wo = math.random() / 10 -- rand freq offset
	local r1, r2, r3 = math.random(), math.random(), math.random()
	RunService.Heartbeat:Connect(function(dt: number)
		PieceModel:PivotTo(
			startCF
				* CFrame.new(0, math.sin(tick() * (math.pi / 2 + wo) + (delay or 0)) / 4, 0)
				* CFrame.Angles(
					math.noise(r1, t) * PIECE_FLOAT_ANG_SCALE,
					math.noise(r2, t) * PIECE_FLOAT_ANG_SCALE,
					math.noise(r3, t) * PIECE_FLOAT_ANG_SCALE
				)
		)
		t += dt / 4
	end)
end

function ClientEffects.highlightPiece(PieceDisplayPart: BasePart): Highlight
	local PieceHighlight = Instance.new("Highlight")
	PieceHighlight.Adornee = PieceDisplayPart

	-- Apply highlight effect to newly hovered piece
	PieceHighlight.Parent = PieceDisplayPart
	PieceHighlight.Adornee = PieceDisplayPart
	PieceHighlight.Enabled = true
	PieceHighlight.FillTransparency = 0.5
	PieceHighlight.FillColor = ChessTypes.hoverHighlightColors.selectColor
	TweenService:Create(
		PieceHighlight,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
		{ FillTransparency = 0.75 }
	):Play()

	return PieceHighlight
end

function ClientEffects.populatePieces(
	Board: Model,
	boardState: ChessTypes.BoardState
): { [string]: ChessTypes.Selectable }
	local BoardRoot = Board.PrimaryPart :: BasePart
	local squareSize = (BoardRoot.Size / 8).X
	local boardOrigin = BoardRoot.CFrame
	local PieceSelectables = {}
	for rank, rankTab in ipairs(boardState) do
		for file, piece in ipairs(rankTab) do
			if piece.Type == "NA" then continue end
			if not ReplicatedStorage.Assets.Pieces:FindFirstChild(piece.Type) then
				warn(`Piece type {piece.Type} from ({rank}, {file}) not found!`)
				continue
			end
			local PieceSelectable =
				ClientEffects.createPieceSelectable(piece.Type, piece.Color, piece.UID)
			local PieceModel = PieceSelectable.Model
			local PiecePart = PieceModel:FindFirstChild("Display") :: BasePart
			PieceModel.Parent = workspace
			PieceModel:PivotTo(
				boardOrigin
					* CFrame.new(
						squareSize * 4.5 - file * squareSize,
						squareSize / 2 + PiecePart.Size.Y / 2,
						rank * squareSize - squareSize * 4.5
					)
			)
			PiecePart.CFrame = PieceModel.WorldPivot
			PieceSelectables[piece.UID] = PieceSelectable
		end
	end
	return PieceSelectables
end

function ClientEffects.createPieceSelectable(
	pieceType: ChessTypes.PieceType,
	pieceColor: ChessTypes.PieceColor,
	pieceUID: string
): ChessTypes.Selectable
	local PieceModel = Instance.new("Model")

	-- Clone and set up part
	local PiecePart = ReplicatedStorage.Assets.Pieces:FindFirstChild(pieceType) :: BasePart
	PiecePart = PiecePart:Clone()
	PiecePart.Color = ChessTypes.pieceColors[pieceColor]
	PiecePart.Size *= ClientEffects.PIECE_SCALE_FACTOR
	PiecePart.Name = "Display"
	PiecePart:SetAttribute("OrigSize", PiecePart.Size)

	-- Create model and mouse hitbox
	local PieceHitbox = Instance.new("Part", PieceModel)
	PieceHitbox.Size = DefaultSquare.Size * 0.85
	PieceHitbox.Transparency = 0.85
	PieceHitbox.Anchored = true
	PieceHitbox.CanCollide = false
	PieceHitbox.CFrame = PiecePart.CFrame
	PiecePart.Parent = PieceModel
	PieceModel.PrimaryPart = PieceHitbox
	PieceModel:SetAttribute("UID", pieceUID)
	PieceModel.Name = tostring(pieceType)

	return {
		Model = PieceModel,
		Display = PiecePart,
		Hitbox = PieceHitbox,
	}
end

local PIECE_START_ANG = math.rad(30)
local PIECE_INC_ANG = (math.pi - 2 * PIECE_START_ANG) / (#ChessTypes.PROMOTION_OPTIONS - 1)
function ClientEffects.promptPromotion(promotedPiece: ChessTypes.Piece, targetCoord: Vector2): Model
	local PromotionContainer = Instance.new("Model", workspace)
	PromotionContainer.Name = "PromotionContainer"

	local PromotionSquare = ChessUtils.getBoardSquareFromCoord(targetCoord, BoardModel)

	local offsetHeight = ReplicatedStorage.Assets.Pieces.Pawn.Size.Y
		* ClientEffects.PIECE_SCALE_FACTOR
	local centerCF = PromotionSquare.CFrame
		* CFrame.new(0, offsetHeight + PromotionSquare.Size.Y / 2, 0)
		* CFrame.Angles(ClientEffects.ANG_FROM_VERT_RAD, 0, 0)
		* CFrame.Angles(-math.pi / 2, 0, math.pi / 2)
	local currentAng = PIECE_START_ANG

	for i, pieceType in ipairs(ChessTypes.PROMOTION_OPTIONS) do
		local PieceSelectable = ClientEffects.createPieceSelectable(
			pieceType :: ChessTypes.PieceType,
			promotedPiece.Color,
			"NA" -- Not sure what this should be for a UI only piece
		)
		local Model = PieceSelectable.Model
		Model.Parent = PromotionContainer
		Model.Name = pieceType
		local spawnCF = centerCF
			* CFrame.Angles(currentAng, 0, 0)
			* CFrame.new(0, offsetHeight * 2.5, 0)
		local Display = Model:FindFirstChild("Display") :: BasePart
		local origSize = Display.Size
		Display.Size = Vector3.zero
		Display.Color = ChessTypes.pieceColors[promotedPiece.Color]
		Display:SetAttribute("OrigSize", origSize)
		ClientEffects.floatPiece(Model, spawnCF, 30, i * math.pi / 6)

		task.delay((i - 1) * 0.1, function()
			TweenService
				:Create(Display, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = origSize })
				:Play()
			ReplicatedStorage.Assets.Sounds.Bubble:Play()
		end)

		currentAng += PIECE_INC_ANG
	end

	return PromotionContainer
end

-- TODO: make this take from existing gui
export type BillboardLabelType = "Persistent" | "Temporary"
function ClientEffects.popupBillboardText(
	text: string,
	Adronee: BasePart,
	offset: Vector3,
	type: BillboardLabelType,
	props: { [string]: any }?
): (BillboardGui, { [string]: (...any) -> ...any })
	local LabelGUI = ReplicatedStorage.Assets.UI.MenuPieceLabel:Clone()
	LabelGUI.Size = UDim2.fromScale(Adronee.Size.Y * 4, Adronee.Size.Y * 2)
	LabelGUI.StudsOffset = Vector3.new(0, Adronee.Size.Y / 2, 0) + offset
	LabelGUI.Parent = Players.LocalPlayer.PlayerGui
	LabelGUI.Adornee = Adronee

	local Canvas = LabelGUI.CanvasGroup
	local Frame = Canvas.Frame
	local textObject
	textObject = RichText:New(Frame, text, props or {
		Looping = true,
		AnimateStyle = "Float",
		AnimateStyleTime = 4,
		AnimateStyleAmplitude = 0.1,
		Font = Enum.Font.DenkOne,
		TextStrokeTransparency = 0,
		BorderSizePixel = 2,
		TextScale = 0.75,
		ContainerHorizontalAlignment = "Center",
	})
	textObject:animateChars(true)
	textObject:Animate(false)

	if type == "Persistent" then return LabelGUI, textObject end

	local FLOAT_AWAY_TIME_S = 2
	delay(FLOAT_AWAY_TIME_S, function()
		TweenService:Create(Canvas, TweenInfo.new(FLOAT_AWAY_TIME_S), {
			GroupTransparency = 1,
		}):Play()
		TweenService:Create(LabelGUI, TweenInfo.new(FLOAT_AWAY_TIME_S), {
			StudsOffset = LabelGUI.StudsOffset + Vector3.new(0, LabelGUI.Size.Y.Scale / 2, 0),
		}):Play()
		delay(FLOAT_AWAY_TIME_S * 1.1, function() LabelGUI:Destroy() end)
	end)

	return LabelGUI, textObject
end

return ClientEffects
