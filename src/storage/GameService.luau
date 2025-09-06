--!strict

-- local STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
local STARTING_FEN = "8/4P/8/8/8/8/4p/8" -- promotion test

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChessUtils = require(ReplicatedStorage.Modules.Libraries.ChessUtils)
local ChessTypes = require(ReplicatedStorage.Modules.Types.ChessTypes)

local GameService = {
	games = {} :: { ChessTypes.ChessGame },
	RemoteEvent = Instance.new("RemoteEvent"),
}

local function fenToBoardState(fen: string): ChessTypes.BoardState
	local state: ChessTypes.BoardState = {}
	local rank, file = 8, 1

	-- Init empty board 2D array
	for i = 1, 8 do
		state[i] = {}
		for j = 1, 8 do
			state[i][j] = ChessUtils.emptyPiece(i, j)
		end
	end

	-- Iterate through FEN string
	for i = 1, #fen do
		local c = fen:sub(i, i)

		-- Number case, skip
		if string.match(c, "%d") then
			file += tonumber(c) :: number
			continue
		end

		-- '/' case, new rank
		if c == "/" then
			rank -= 1
			file = 1
			continue
		end

		-- Alpha char case, create new piece
		local piece: ChessTypes.Piece = {
			Type = ChessTypes.fenLookUp[string.lower(c)],
			Color = (
					string.match(c, "%u") and "White" or (
						string.match(c, "%l") and "Black" or "Env"
					)
				) :: ChessTypes.PieceColor,
			UID = HttpService:GenerateGUID(),
			Coord = Vector2.new(rank, file),
			HasMoved = false,
		}
		state[rank][file] = piece
		file += 1

		-- Handle king castling initial conditions
		if piece.Type == "King" then
			piece.CanCastleLong = true
			piece.CanCastleShort = true
		end
	end

	return state
end

local function clearEnPassantFlags(boardState: ChessTypes.BoardState, color: ChessTypes.PieceColor)
	for _, rank in pairs(boardState) do
		for _, piece in pairs(rank) do
			if piece.Color == color and piece.CanEnPassant then piece.CanEnPassant = false end
		end
	end
end

local function switchTurns(chessGame: ChessTypes.ChessGame)
	chessGame.turn = (chessGame.turn == "Black" and "White" or "Black") :: ChessTypes.PieceColor
end

local function getGameFromPlayer(Player: Player): ChessTypes.ChessGame
	local chessGame: ChessTypes.ChessGame
	local PlayerColor: ChessTypes.PieceColor
	for _, game in pairs(GameService.games) do
		if game.WhitePlayer == Player or game.BlackPlayer == Player then
			PlayerColor = (
				game.WhitePlayer == Player and "White" or "Black"
			) :: ChessTypes.PieceColor
			if game.turn ~= PlayerColor then -- Out of turn request, cancel
				warn(`{Player} attempted to request move when out of turn!`)
				-- return
			end
			chessGame = game
			break
		end
	end
	return chessGame
end

local function updateGameForPlayers(chessGame: ChessTypes.ChessGame)
	if chessGame.BlackPlayer ~= "AI" then
		GameService.RemoteEvent:FireClient(chessGame.BlackPlayer, "UpdateGame", chessGame)
	end
	if chessGame.WhitePlayer ~= "AI" then
		GameService.RemoteEvent:FireClient(chessGame.WhitePlayer, "UpdateGame", chessGame)
	end
end

local function playerPlacePiece(Player: Player, targetCoord: Vector2, pieceUID: string)
	-- Find player's game
	local activeGame = getGameFromPlayer(Player)
	if not activeGame then return end
	local boardState = activeGame.state

	-- Get the piece from provided UID
	local piece = ChessUtils.getPieceFromUID(pieceUID, boardState)
	if not piece then return end

	-- Check to make sure target coord is valid
	for _, coord in pairs(ChessUtils.getValidMoves(piece, boardState)) do
		if coord == targetCoord then
			-- Clear any en passant flags
			clearEnPassantFlags(boardState, piece.Color)

			-- Move piece
			if not ChessUtils.movePiece(boardState, piece, coord) then
				-- Normal turn end
				switchTurns(activeGame)
			else
				-- Prompt promotion
				activeGame.promotingPiece = ChessUtils.getPieceFromUID(pieceUID, boardState)
				GameService.RemoteEvent:FireClient(Player, "PromptPromotion", targetCoord, pieceUID)
			end

			-- Update players' games
			updateGameForPlayers(activeGame)
			return
		end
	end
end

local function promotePiece(Player: Player, pieceType: ChessTypes.PieceType)
	-- Find player's game
	local activeGame = getGameFromPlayer(Player)
	if not activeGame or not activeGame.promotingPiece then return end
	local boardState = activeGame.state
	ChessUtils.replacePiece(boardState, activeGame.promotingPiece.Coord, {
		Type = pieceType,
		Color = (Player == activeGame.WhitePlayer and "White" or "Black") :: ChessTypes.PieceColor,
		UID = HttpService:GenerateGUID(),
		Coord = activeGame.promotingPiece.Coord,
		HasMoved = false,
	})
	activeGame.promotingPiece = nil
	updateGameForPlayers(activeGame)
end

function GameService.init(RuntimeFolder: Folder, RemotesFolder: Folder)
	-- Setup remote event
	GameService.RemoteEvent.Name = "GameServiceRemote"
	GameService.RemoteEvent.Parent = RemotesFolder
	GameService.RemoteEvent.OnServerEvent:Connect(function(Player: Player, eventName: string, ...)
		if eventName == "RequestGame" then
			local newGame = GameService.createGame(Player)
			table.insert(GameService.games, newGame)
			GameService.RemoteEvent:FireClient(Player, "StartGame", newGame)
		elseif eventName == "PlacePiece" then
			playerPlacePiece(Player, ...)
		elseif eventName == "PromotePiece" then
			promotePiece(Player, ...)
		end
	end)
end

function GameService.start() end

function GameService.createGame(Player: Player): ChessTypes.ChessGame
	local newChessGame: ChessTypes.ChessGame = {
		state = fenToBoardState(STARTING_FEN),
		turn = "White",
		WhitePlayer = Player,
		-- BlackPlayer = "AI",
		BlackPlayer = Player,
	}
	return newChessGame
end

return GameService
