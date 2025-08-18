--!strict

local STARTING_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

local Players = game:GetService("Players")

type ChessGame = {
	stateFEN: string,
	turn: "black" | "white",
	Player: Player,
}

local GameService = {
	games = {},
	RemoteEvent = Instance.new("RemoteEvent"),
}

local function resetBoard() end

local function updateBoard(newState: string) end

function GameService.init(RuntimeFolder: Folder, RemotesFolder: Folder)
	-- Setup remote event
	GameService.RemoteEvent.Name = "GameServiceRemote"
	GameService.RemoteEvent.Parent = RemotesFolder
	GameService.RemoteEvent.OnServerEvent:Connect(function(Player: Player, eventName: string)
		if eventName == "RequestGame" then
			table.insert(GameService.games, GameService.createGame(Player))
			GameService.RemoteEvent:FireClient(Player, "StartGame")
			print(`{Player.Name} starting game`)
		end
	end)
end

function GameService.start() end

function GameService.createGame(Player: Player): ChessGame
	local newChessGame: ChessGame = {
		stateFEN = STARTING_FEN,
		turn = "white",
		Player = Player,
	}

	return newChessGame
end

return GameService
