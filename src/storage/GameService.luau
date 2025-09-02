--!strict

local STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
-- local STARTING_FEN = "8/8/8/3P/3R/8/3p/8"

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
			Color = (string.match(c, "%u") and "White" or "Black") :: ChessTypes.PieceColor,
			UID = HttpService:GenerateGUID(),
			Coord = Vector2.new(rank, file),
			HasMoved = false,
		}
		state[rank][file] = piece
		file += 1
	end

	return state
end

local function resetBoard() end

local function updateBoard(newState: string) end

local function playerPlacePiece(Player: Player, targetCoord: Vector2, pieceUID: string)
	-- Find player's game
	local activeGame: ChessTypes.ChessGame
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
			activeGame = game
			break
		end
	end
	if not activeGame then return end
	local boardState = activeGame.state

	-- Get the piece from provided UID
	local piece = ChessUtils.getPieceFromUID(pieceUID, boardState)
	if not piece then return end

	-- Check to make sure target coord is valid
	for _, coord in pairs(ChessUtils.getValidMoves(piece, boardState)) do
		if coord == targetCoord then
			-- Move piece
			ChessUtils.movePiece(boardState, piece, coord)

			-- Switch turns
			activeGame.turn = (
				PlayerColor == "Black" and "White" or "Black"
			) :: ChessTypes.PieceColor

			-- Update players
			if activeGame.BlackPlayer ~= "AI" then
				GameService.RemoteEvent:FireClient(activeGame.BlackPlayer, "UpdateGame", activeGame)
			end
			if activeGame.WhitePlayer ~= "AI" then
				GameService.RemoteEvent:FireClient(activeGame.WhitePlayer, "UpdateGame", activeGame)
			end
			return
		end
	end
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
		end
	end)
end

function GameService.start() end

function GameService.createGame(Player: Player): ChessTypes.ChessGame
	local newChessGame: ChessTypes.ChessGame = {
		state = fenToBoardState(STARTING_FEN),
		turn = "White",
		WhitePlayer = Player,
		BlackPlayer = "AI",
	}
	return newChessGame
end

return GameService
