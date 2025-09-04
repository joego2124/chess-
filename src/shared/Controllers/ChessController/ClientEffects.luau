--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RichText = require(ReplicatedStorage.Modules.Libraries.RichText)
local ChessTypes = require(ReplicatedStorage.Modules.Types.ChessTypes)

-- TODO: redundant reference
local DefaultSquare = ReplicatedStorage.Assets.Board.DefaultSquare

local ClientEffects = {}

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

function ClientEffects.createPieceModel(pieceType: ChessTypes.PieceType): Model
	local Model = Instance.new("Model")
	local PiecePart = ReplicatedStorage.Assets.Pieces[pieceType]:Clone()
	PiecePart.Anchored = true
	PiecePart.Parent = Model
	PiecePart.Name = "Display"
	local Hitbox = Instance.new("Part", Model)
	Hitbox.Size = PiecePart.Size
	Hitbox.Transparency = 1
	Hitbox.CanCollide = false
	Hitbox.Anchored = true
	Hitbox.CFrame = PiecePart.CFrame
	Model.PrimaryPart = Hitbox
	return Model
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

local PROMOTION_OPTIONS: { ChessTypes.PieceType } = {
	"Knight",
	"Bishop",
	"Rook",
	"Queen",
}
local STARTING_ANG = math.rad(0)
local PIECE_INC_ANG = (180 - 2 * STARTING_ANG) / #PROMOTION_OPTIONS
function ClientEffects.promptPromotion(PieceModel: Model, targetCoord: Vector2): Model
	local PromotionContainer = Instance.new("Model", workspace)
	PromotionContainer.Name = "PromotionContainer"

	local PawnDisplay = PieceModel:FindFirstChild("Display") :: BasePart
	local pieceHeight = PawnDisplay.Size.Y
	local centerCF = PieceModel.WorldPivot
		* CFrame.new(0, pieceHeight * 2, pieceHeight)
		* CFrame.Angles(-math.pi / 2, 0, math.pi / 2)
	local currentAng = STARTING_ANG

	for i, pieceType in ipairs(PROMOTION_OPTIONS) do
		local Model = ClientEffects.createPieceModel(pieceType :: ChessTypes.PieceType)
		Model.Parent = PromotionContainer
		Model:ScaleTo(ClientEffects.PIECE_SCALE_FACTOR)
		Model.Name = pieceType
		local spawnCF = centerCF
			* CFrame.Angles(currentAng, 0, 0)
			* CFrame.new(0, pieceHeight * (2 + 0 * math.sin(currentAng)), 0)

		local Display = Model:FindFirstChild("Display") :: BasePart
		local origSize = Display.Size
		Display.Size = Vector3.zero
		Display.Color = PawnDisplay.Color
		Display:SetAttribute("OrigSize", origSize)
		ClientEffects.floatPiece(
			Model,
			CFrame.lookAt(spawnCF.Position, workspace.CurrentCamera.CFrame.Position),
			10,
			i * math.pi / 6
		)

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

return ClientEffects
