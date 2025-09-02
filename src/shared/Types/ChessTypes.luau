--!strict

local ChessTypes = {}

export type PieceType = "Pawn" | "Knight" | "Bishop" | "Rook" | "Queen" | "King" | "NA"
export type PieceColor = "White" | "Black"
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
}

ChessTypes.colors = {
	Black = Color3.fromRGB(30, 40, 50),
	White = Color3.fromRGB(200, 200, 160),
} :: { [PieceColor]: Color3 }

ChessTypes.fenLookUp = {
	p = "Pawn",
	n = "Knight",
	b = "Bishop",
	r = "Rook",
	q = "Queen",
	k = "King",
} :: { [string]: PieceType }

ChessTypes.hoverHighlightColors = {
	selectColor = Color3.fromRGB(0, 170, 255),
}

ChessTypes.menuColors = {
	playAIColor = Color3.fromRGB(0, 170, 255),
}

return ChessTypes
