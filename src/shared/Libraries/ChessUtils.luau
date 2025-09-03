--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
			local attackCoord = piece.Coord + Vector2.new(0, file)
			local attackedPiece = boardState[attackCoord.X][attackCoord.Y]
			if
				attackedPiece
				and not ChessUtils.isPieceEmpty(attackedPiece)
				and attackedPiece.Color ~= piece.Color
				and attackedPiece.CanEnPassant
			then
				table.insert(validCoords, attackCoord + Vector2.new(movementDir, 0))
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
		-- Default valid moves' coords
		local coords = straightAndDiagonal(piece, boardState, 1)

		-- Helper func for checking if any pieces are in the way of castling
		local function checkCastlingSquares(side: "Short" | "Long"): boolean
			for i = piece.Coord.Y, (side == "Short" and #boardState or 1), (side == "Short" and 1 or -1) do
				local p = boardState[piece.Color == "Black" and 8 or 1][i]
				if p == piece or p.Type == "Rook" then continue end
				if p.Type ~= "NA" then return false end
			end
			return true
		end

		-- Check for both long and short castling
		if piece.CanCastleLong and checkCastlingSquares("Long") then
			table.insert(coords, piece.Coord + Vector2.new(0, -2))
		end
		if piece.CanCastleShort and checkCastlingSquares("Short") then
			table.insert(coords, piece.Coord + Vector2.new(0, 2))
		end

		return coords
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
	local targetPiece = boardState[coord.X][coord.Y]

	-- Check special rules first
	if not pieceMoved.HasMoved then
		-- Set pawn en passant flag
		if pieceMoved.Type == "Pawn" and math.abs(coord.X - pieceMoved.Coord.X) > 1 then
			pieceMoved.CanEnPassant = true
		end

		-- Handle king castling rules
		if pieceMoved.Type == "King" then
			pieceMoved.CanCastleLong = false
			pieceMoved.CanCastleShort = false

			local moveDiff = (coord - pieceMoved.Coord).Y
			if math.abs(moveDiff) > 1 then
				local rank = pieceMoved.Color == "White" and 1 or 8
				ChessUtils.movePiece(
					boardState,
					boardState[rank][moveDiff > 0 and 8 or 1], -- moveDiff < 0 is short
					Vector2.new(rank, moveDiff > 0 and coord.Y - 1 or coord.Y + 1)
				)
			end
		end

		-- Revoke castling privilege
		if pieceMoved.Type == "Rook" then
			local kingPiece: ChessTypes.Piece
			for _, p in pairs(boardState[pieceMoved.Color == "White" and 1 or 8]) do
				if p.Type == "King" then
					kingPiece = p
					break
				end
			end
			if not kingPiece then
				warn(`Trying to revoke castling privilege but {pieceMoved.Color}'s king not found!`)
			end
			if pieceMoved.Coord.Y == 1 and kingPiece then kingPiece.CanCastleLong = false end
			if pieceMoved.Coord.Y == 8 and kingPiece then kingPiece.CanCastleShort = false end
		end

		pieceMoved.HasMoved = true
	end

	-- Handle en passant capture
	if pieceMoved.Type == "Pawn" and targetPiece.Type == "NA" and coord.Y ~= pieceMoved.Coord.Y then
		local capturedPiece = boardState[pieceMoved.Coord.X][coord.Y]
		if capturedPiece and capturedPiece.Type == "Pawn" and capturedPiece.CanEnPassant then
			ChessUtils.removePiece(boardState, capturedPiece)
		end
	end

	-- Copy over piece to board slot
	for prop, _ in pairs(pieceMoved) do
		targetPiece[prop] = pieceMoved[prop]
	end
	targetPiece.Coord = coord

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
