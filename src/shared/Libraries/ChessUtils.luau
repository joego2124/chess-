--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChessTypes = require(ReplicatedStorage.Modules.Types.ChessTypes)

local ChessUtils = {}

type moveFunc = (ChessTypes.Piece, ChessTypes.BoardState) -> { Vector2 }

local straightMoves = function(
	piece: ChessTypes.Piece,
	boardState: ChessTypes.BoardState,
	magnitude: number
): { Vector2 }
	local validCoords = {}
	local origin = piece.Coord

	for _, dir in pairs({ Vector2.xAxis, -Vector2.xAxis, Vector2.yAxis, -Vector2.yAxis }) do
		for i = 1, magnitude do
			local coord = origin + (dir * i)
			if coord.X < 1 or coord.X > 8 or coord.Y < 1 or coord.Y > 8 then break end
			local coordPiece = boardState[coord.X][coord.Y]
			if ChessUtils.isCoordEmpty(coord, boardState) then
				table.insert(validCoords, coord)
			else
				if coordPiece.Color ~= piece.Color then table.insert(validCoords, coord) end
				break
			end
		end
	end

	return validCoords
end

local diagonalMoves = function(
	piece: ChessTypes.Piece,
	boardState: ChessTypes.BoardState,
	magnitude: number
): { Vector2 }
	local validCoords = {}
	local origin = piece.Coord

	for fileDir = -1, 1, 1 do
		if fileDir == 0 then continue end
		for rankDir = -1, 1, 1 do
			if rankDir == 0 then continue end
			for i = 1, magnitude do
				local coord = origin + Vector2.new(rankDir * i, fileDir * i)
				if coord.X < 1 or coord.X > 8 or coord.Y < 1 or coord.Y > 8 then break end
				local coordPiece = boardState[coord.X][coord.Y]
				if ChessUtils.isCoordEmpty(coord, boardState) then
					table.insert(validCoords, coord)
				else
					if coordPiece.Color ~= piece.Color then table.insert(validCoords, coord) end
					break
				end
			end
		end
	end

	return validCoords
end

local straightAndDiagonal = function(
	piece: ChessTypes.Piece,
	boardState: ChessTypes.BoardState,
	magnitude: number
): { Vector2 }
	local validCoords = {}

	for _, moves in pairs({
		straightMoves(piece, boardState, magnitude),
		diagonalMoves(piece, boardState, magnitude),
	}) do
		for _, coord in pairs(moves) do
			table.insert(validCoords, coord)
		end
	end

	return validCoords
end

ChessUtils.pieceMoves = {

	Pawn = function(piece: ChessTypes.Piece, boardState: ChessTypes.BoardState): { Vector2 }
		local movementDir = piece.Color == "White" and 1 or -1

		-- Default movement
		local validCoords = {}
		local firstMoveCoord = piece.Coord + Vector2.new(movementDir, 0)
		if firstMoveCoord.X < 1 or firstMoveCoord.X > 8 then return validCoords end
		if ChessUtils.isCoordEmpty(firstMoveCoord, boardState) then
			table.insert(validCoords, firstMoveCoord)
		end

		-- Initial double move
		if not piece.HasMoved and #validCoords > 0 then
			local doubleMoveCoord = piece.Coord + Vector2.new(movementDir * 2, 0)
			if ChessUtils.isCoordEmpty(doubleMoveCoord, boardState) then
				table.insert(validCoords, doubleMoveCoord)
			end
		end

		-- Attacking movement
		for file = -1, 1, 1 do
			if file == 0 then continue end

			-- Check en passant first
			-- TODO: need to somehow mark as en passant attack
			local attackCoord = piece.Coord + Vector2.new(0, file)
			local attackedPiece = boardState[attackCoord.X][attackCoord.Y]
			if
				attackedPiece
				and not ChessUtils.isPieceEmpty(attackedPiece)
				and attackedPiece.Color ~= piece.Color
				and attackedPiece.CanEnPassant
			then
				table.insert(validCoords, attackCoord + Vector2.new(movementDir, file))
			end

			-- Normal attack
			attackCoord = piece.Coord + Vector2.new(movementDir, file)
			attackedPiece = boardState[attackCoord.X][attackCoord.Y]
			if
				not attackedPiece
				or ChessUtils.isPieceEmpty(attackedPiece)
				or attackedPiece.Color == piece.Color
			then
				continue
			end
			table.insert(validCoords, attackCoord)
		end

		return validCoords
	end,

	Knight = function(piece: ChessTypes.Piece, boardState: ChessTypes.BoardState): { Vector2 }
		local validCoords = {}

		local moveOffsets = {
			Vector2.new(1, 2),
			Vector2.new(1, -2),
			Vector2.new(-1, 2),
			Vector2.new(-1, -2),
			Vector2.new(2, 1),
			Vector2.new(2, -1),
			Vector2.new(-2, 1),
			Vector2.new(-2, -1),
		}
		for _, offset in pairs(moveOffsets) do
			local coord = piece.Coord + offset
			if coord.X > 8 or coord.X < 1 or coord.Y > 8 or coord.Y < 1 then continue end
			local targetSquare = boardState[coord.X][coord.Y]
			if not ChessUtils.isPieceEmpty(targetSquare) and targetSquare.Color == piece.Color then
				continue
			end
			table.insert(validCoords, coord)
		end

		return validCoords
	end,

	Bishop = function(piece: ChessTypes.Piece, boardState: ChessTypes.BoardState): { Vector2 }
		return diagonalMoves(piece, boardState, 8)
	end,

	Rook = function(piece: ChessTypes.Piece, boardState: ChessTypes.BoardState): { Vector2 }
		return straightMoves(piece, boardState, 8)
	end,

	Queen = function(piece: ChessTypes.Piece, boardState: ChessTypes.BoardState): { Vector2 }
		return straightAndDiagonal(piece, boardState, 8)
	end,

	King = function(piece: ChessTypes.Piece, boardState: ChessTypes.BoardState): { Vector2 }
		return straightAndDiagonal(piece, boardState, 1)
	end,
} :: { [ChessTypes.PieceType]: moveFunc }

function ChessUtils.emptyPiece(rank: number, file: number): ChessTypes.Piece
	local piece: ChessTypes.Piece = {
		Type = "NA",
		Color = "Black",
		UID = "",
		Coord = Vector2.new(rank, file),
		HasMoved = false,
	}
	return piece
end

function ChessUtils.movePiece(
	boardState: ChessTypes.BoardState,
	pieceMoved: ChessTypes.Piece,
	coord: Vector2
)
	-- Copy over piece to board slot
	local origCoord = pieceMoved.Coord
	local targetPiece = boardState[coord.X][coord.Y]
	for prop, _ in pairs(targetPiece) do
		targetPiece[prop] = pieceMoved[prop]
	end
	targetPiece.Coord = coord

	-- Check special rules
	if not targetPiece.HasMoved then
		if targetPiece.Type == "Pawn" then
			if not targetPiece.HasMoved then targetPiece.CanEnPassant = true end
			if not targetPiece.HasMoved then targetPiece.HasMoved = true end
		end
		if targetPiece.Type == "King" then
			targetPiece.CanCastleLong = false
			targetPiece.CanCastleShort = false
		end
		if targetPiece.Type == "Rook" then
			if origCoord.Y == 1 then targetPiece.CanCastleLong = false end
			if origCoord.Y == 8 then targetPiece.CanCastleShort = false end
		end
	end

	targetPiece.HasMoved = true

	ChessUtils.removePiece(boardState, pieceMoved)
end

function ChessUtils.removePiece(boardState: ChessTypes.BoardState, piece: ChessTypes.Piece)
	for rank = 1, 8 do
		for file = 1, 8 do
			local p = boardState[rank][file]
			if p ~= piece then continue end
			p.Type = "NA"
			p.UID = ""
			return
		end
	end
end

function ChessUtils.isPieceEmpty(piece: ChessTypes.Piece): boolean return piece.Type == "NA" end

function ChessUtils.isCoordEmpty(coord: Vector2, boardState: ChessTypes.BoardState): boolean
	return ChessUtils.isPieceEmpty(boardState[coord.X][coord.Y])
end

function ChessUtils.getValidMoves(
	piece: ChessTypes.Piece,
	boardState: ChessTypes.BoardState
): { Vector2 }
	return ChessUtils.pieceMoves[piece.Type](piece, boardState)
end

-- Client side model util funcs

function ChessUtils.getPieceFromModel(
	PieceModel: Model,
	boardState: ChessTypes.BoardState
): ChessTypes.Piece?
	local UID = PieceModel:GetAttribute("UID")
	for _, rank in ipairs(boardState) do
		for _, piece in ipairs(rank) do
			if piece.UID ~= UID then continue end
			return piece
		end
	end
	return
end

function ChessUtils.getPieceFromUID(
	UID: string,
	boardState: ChessTypes.BoardState
): ChessTypes.Piece?
	for _, rank in ipairs(boardState) do
		for _, piece in ipairs(rank) do
			if piece.UID ~= UID then continue end
			return piece
		end
	end
	return
end

function ChessUtils.getBoardSquareFromCoord(coord: Vector2, Board: Model): BasePart
	return (Board:FindFirstChild(tostring(coord.X)) :: BasePart):FindFirstChild(
			tostring(coord.Y)
		) :: BasePart
end

return ChessUtils
