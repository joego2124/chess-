--!strict

local ChessTypes = {}

export type PieceType = "Pawn" | "Knight" | "Bishop" | "Rook" | "Queen" | "King" | "NA"
export type PieceColor = "White" | "Black" | "Env"
export type Piece = {
	Type: PieceType,
	Color: PieceColor,
	UID: string,
	Coord: Vector2,
	CanEnPassant: boolean?,
	CanCastleLong: boolean?,
	CanCastleShort: boolean?,
	HasMoved: boolean,
}

export type BoardState = { { Piece } }

export type ChessGame = {
	state: BoardState,
	turn: PieceColor,
	WhitePlayer: Player | "AI",
	BlackPlayer: Player | "AI",
	promotingPiece: Piece?,
}

ChessTypes.boardColors = {
	Black = Color3.fromRGB(120, 82, 64),
	White = Color3.fromRGB(234, 184, 146),
} :: { [PieceColor]: Color3 }

ChessTypes.pieceColors = {
	Black = Color3.fromRGB(60, 40, 30),
	White = Color3.fromRGB(220, 200, 160),
} :: { [PieceColor]: Color3 }

ChessTypes.fenLookUp = {
	p = "Pawn",
	n = "Knight",
	b = "Bishop",
	r = "Rook",
	q = "Queen",
	k = "King",
} :: { [string]: PieceType }

ChessTypes.PROMOTION_OPTIONS = {
	"Knight",
	"Bishop",
	"Rook",
	"Queen",
} :: { PieceType }

ChessTypes.hoverHighlightColors = {
	selectColor = Color3.fromRGB(0, 170, 255),
	inactiveSelectColor = Color3.fromHSV(0, 0, 0.25),
	pieceMoveSquareColor = Color3.fromRGB(255, 200, 0),
}

ChessTypes.menuColors = {
	playAIColor = Color3.fromRGB(0, 170, 255),
}

return ChessTypes
