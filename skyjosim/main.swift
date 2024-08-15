import Foundation
import simd

let oneToTwelve: [Int] = [Int](1...12).flatMap { number in return [Int](repeating: number, count: 10) }
let cards: [Int] = [Int](repeating: -2, count: 5) + [Int](repeating: -1, count: 10) + [Int](repeating: 0, count: 15)
+ oneToTwelve

protocol Estimatable {
    var estimatedValue: Int { get }
}

protocol Vectorizable {
    var vectorized: [Double] { get }
}

func sigmoid(_ x: Double) -> Double {
    return 1.0 / (1.0 + exp(-x))
}

enum FieldState: Equatable, CustomDebugStringConvertible, Estimatable, Vectorizable {
    case gone
    case revealed(Int)
    case unrevealed(Int)
    
    func redacted() -> RedactedFieldState {
        return switch self {
        case .gone:
            .gone
        case .revealed(let number):
            .revealed(number)
        case .unrevealed(_):
            .unrevealed
        }
    }
    
    var estimatedValue: Int {
        return switch self {
        case .gone: 0
        case .revealed(let number), .unrevealed(let number): number
        }
    }
    
    var vectorized: [Double] {
        let value: Int = switch self {
        case .gone:
            -1
        case .revealed(let number):
            number + 2
        case .unrevealed(let number):
            -(number + 10)
        }
        
        return [Double(value)]
    }
    
    var debugDescription: String {
        return switch self {
        case .gone: "////"
        case .revealed(let number): "[" + "\(number)".padLeft(toLen: 2) + "]"
        case .unrevealed(let number): "{" + "\(number)".padLeft(toLen: 2) + "}"
        }
    }
}

extension String {
    func padLeft(toLen: Int) -> String {
        String(repeating: " ", count: max(toLen - self.count, 0)) + self
    }
}

enum RedactedFieldState: Equatable, CustomDebugStringConvertible, Estimatable, Vectorizable {
    case gone
    case revealed(Int)
    case unrevealed
    
    var debugDescription: String {
        return switch self {
        case .gone: "////"
        case .revealed(let number): "[" + "\(number)".padLeft(toLen: 2) + "]"
        case .unrevealed: "****"
        }
    }
    
    var estimatedValue: Int {
        return switch self {
        case .gone, .unrevealed: 0
        case .revealed(let number): number
        }
    }
    
    var vectorized: [Double] {
        let value: Int = switch self {
        case .gone:
            -1
        case .revealed(let number):
            number + 2
        case .unrevealed:
            -2
        }
        
        return [Double(value)]
    }
}

extension PlayerField: CustomDebugStringConvertible where FieldStateType: CustomDebugStringConvertible & Estimatable {
    var debugDescription: String {
        var s = ""
        s += String(repeating: "-", count: 2 + (4 * 5 + 1)) + "\n"
        for row in 0...2 {
            s += "|"
            for col in 0...3 {
                s += " " + fields[col][row].debugDescription
            }
            s += " |\n"
        }
        s += String(repeating: "-", count: 2 + (4 * 5 + 1)) + "\n"
        s += "sum = \(sum())"
        return s
    }
}

extension PlayerField: Vectorizable where FieldStateType: Vectorizable {
    var vectorized: [Double] {
        fields.flatMap { $0.flatMap { $0.vectorized } }
    }
}

struct PlayerField<FieldStateType: Estimatable> {
    let fields: [[FieldStateType]]
    
    init(fields: [FieldStateType]) {
        var tempFields: [[FieldStateType]] = []
        for col in 0...3 {
            tempFields.append([])
            for row in 0...2 {
                tempFields[col].append(fields[col * 3 + row])
            }
        }
        self.fields = tempFields
    }
    
    init(fields: [[FieldStateType]]) {
        self.fields = fields
    }
    
    static var fieldTuples: [(Int, Int)] {
        Array(0...3).flatMap { col in Array(0...2).map { row in (row, col) } }
    }
    
    func reveal(col: Int, row: Int) -> Self where FieldStateType == FieldState {
        guard case .unrevealed(let number) = fields[col][row] else {
            fatalError("wrong move")
        }
        
        var tempFields = fields
        tempFields[col][row] = .revealed(number)
        if tempFields[col].allSatisfy({ $0 == .revealed(number) }) {
            tempFields[col] = tempFields[col].map { _ in .gone }
        }
        
        return PlayerField(fields: tempFields)
    }
    
    func swapInto(col: Int, row: Int, card: Int) -> (Self, [Int]) where FieldStateType == FieldState {
        var tempFields = fields
        switch fields[col][row] {
        case .gone: fatalError("wrong move")
        case .revealed(let number), .unrevealed(let number):
            tempFields[col][row] = .revealed(card)
            if tempFields[col].allSatisfy({ $0 == .revealed(card) }) {
                tempFields[col] = tempFields[col].map { _ in .gone }
            }
            return (.init(fields: tempFields), [number])
        }
    }
    
    func redacted() -> PlayerField<RedactedFieldState> where FieldStateType == FieldState {
        .init(fields: fields.map { $0.map { $0.redacted() } })
    }
    
    func sum() -> Int {
        fields.reduce(0) { acc1, next1 in
            acc1 + next1.reduce(0) { acc2, next2 in
                acc2 + next2.estimatedValue
            }
        }
    }
}

struct GameState: CustomDebugStringConvertible {
    let middleCard: Int
    let stack: [Int]
    let fields: [PlayerField<FieldState>]
    
    func validMoves(for playerId: Int) -> [GameMove] {
        return [.noMove, .end] + PlayerField<FieldState>.fieldTuples.flatMap { row, col in
            let base: [GameMove] = [.drawTo(col: col, row: row), .swapMiddle(col: col, row: row)]
            guard case .unrevealed(_) = fields[playerId].fields[col][row] else {
                return base
            }
            
            return base + [.reveal(col: col, row: row)]
        }
    }
    
    func applying(move: GameMove, playerId: Int) -> GameState {
        let field = fields[playerId]
        switch move {
        case .reveal(let col, let row):
            let newField = field.reveal(col: col, row: row)
            var tempFields = fields
            tempFields[playerId] = newField
            return .init(
                middleCard: middleCard,
                stack: stack,
                fields: tempFields
            )
            
        case .swapMiddle(let col, let row):
            let (newField, discardedCards) = field.swapInto(col: col, row: row, card: middleCard)
            var tempFields = fields
            tempFields[playerId] = newField
            return .init(
                middleCard: discardedCards.last!,
                stack: stack,
                fields: tempFields
            )
            
        case .drawTo(let col, let row):
            var currentStack = stack
            let drawnCard = currentStack.removeLast()
            let (newField, _) = field.swapInto(col: col, row: row, card: drawnCard)
            var tempFields = fields
            tempFields[playerId] = newField
            return .init(
                middleCard: middleCard,
                stack: currentStack,
                fields: tempFields
            )
        
        case .end: fatalError("handle earlier")
        case .noMove:
            debugPrint("no move was made")
            return self
        }
    }
    
    func redacted() -> RedactedGameState {
        .init(
            middleCard: middleCard,
            fields: fields.map { $0.redacted() }
        )
    }
    
    var debugDescription: String {
        var s = "middleCard: \(middleCard)\n"
        s += "stack: \(stack)\n"
        for (index, player) in fields.enumerated() {
            s += "player: \(index)\n"
            s += player.debugDescription + "\n"
        }
        return s
    }
}

struct RedactedGameState: CustomDebugStringConvertible {
    let middleCard: Int
    let fields: [PlayerField<RedactedFieldState>]
    
    var debugDescription: String {
        var s = "middleCard: \(middleCard)\n"
        for (index, player) in fields.enumerated() {
            s += "player: \(index)\n"
            s += player.debugDescription + "\n"
        }
        return s
    }
    
    func validMoves(for playerId: Int) -> [GameMove] {
        return [.noMove, .end] + PlayerField<FieldState>.fieldTuples.flatMap { row, col in
            let base: [GameMove] = [.drawTo(col: col, row: row), .swapMiddle(col: col, row: row)]
            guard case .unrevealed = fields[playerId].fields[col][row] else {
                return base
            }
            
            return base + [.reveal(col: col, row: row)]
        }
    }
}

extension RedactedGameState: Vectorizable {
    var vectorized: [Double] {
        let values = [Double(middleCard)] + fields.flatMap { $0.vectorized }
        return values
    }
}

enum GameMove: Equatable {
    case reveal(col: Int, row: Int)
    case swapMiddle(col: Int, row: Int)
    case drawTo(col: Int, row: Int)
    case end
    case noMove
}

open class PlayerStrategy {
    func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove {
        return .swapMiddle(col: 0, row: 0)
    }
}

extension Array {
    mutating func popLast(_ k: Int) -> [Element] {
        var result: Self = []
        for _ in 0..<k {
            if let element = self.popLast() {
                result.append(element)
            }
        }
        return result
    }
}

final class GameLoop {
    var currentGameState: GameState
    let players: [PlayerStrategy]
    var currentPlayer: Int = 0
    var endsAt: Int?
    
    init(players: [PlayerStrategy]) {
        self.players = players
        
        var shuffledCards = cards.shuffled()
        
        let middleCard = shuffledCards.popLast()!
        
        let fields: [PlayerField<FieldState>] = Array(0...3).map { playerId in
            return .init(fields: shuffledCards.popLast(12).map { .unrevealed($0 )})
        }
        
        self.currentGameState = .init(
            middleCard: middleCard,
            stack: shuffledCards,
            fields: fields
        )
    }
    
    func initialize() {
        var shuffledCards = cards.shuffled()
        let middleCard = shuffledCards.popLast()!
        let fields: [PlayerField<FieldState>] = Array(0...3).map { playerId in
            return .init(fields: shuffledCards.popLast(12).map { .unrevealed($0 )})
        }
        
        self.currentGameState = .init(
            middleCard: middleCard,
            stack: shuffledCards,
            fields: fields
        )
    }
    
    func step() {
        defer {
            currentPlayer = (currentPlayer + 1) % players.count
        }
        
        let strategy = players[currentPlayer]
        
        let move = strategy.decision(state: currentGameState.redacted(), ownPlayerId: currentPlayer)
        
        if move == .end {
            guard endsAt == nil else { fatalError("only one can finish") }
            endsAt = currentPlayer
            return
        }
        
        currentGameState = currentGameState.applying(move: move, playerId: currentPlayer)
    }
    
    func run() -> [Int:Int] {
        initialize()
        while true {
            if let endsAt, currentPlayer == endsAt {
                break
            }
            
            step()
        }
        
        var scores = Dictionary(uniqueKeysWithValues: currentGameState.fields.enumerated().map { index, field in
            return (index, field.sum())
        })
        
        if let endsAt,
           let minimumScore = scores.filter({ $0.key != endsAt }).values.min(),
           let score = scores[endsAt],
           score >= minimumScore {
            scores[endsAt] = 2 * score
            print("end player has lost")
        }

        return scores
    }
    
    func playerWon(scores: [Int:Int]) -> Int {
        scores.min { tupleA, tupleB in
            tupleA.1 < tupleB.1
        }?.0 ?? -1
    }
    
    func evaluate() -> Int {
        let scores = run()
        return playerWon(scores: scores)
    }
}

class EndPlayer: PlayerStrategy {
    var move = 0
    let max = 12
    override func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove {
        move += 1
        if move == max {
            return .end
        }
        
        let row = (move - 1) % 3
        let col = ((move - 1) - row) / 4
        return .swapMiddle(col: col, row: row)
    }
}

class SwapPlayer: PlayerStrategy {
    var move = 0
    override func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove {
        move += 1
        return .swapMiddle(col: 0, row: (move - 1) % 3)
    }
}

class TomPlayer: PlayerStrategy {
    override func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove {
        let alertPlayers = playersWithImminentDestruction(state: state, for: state.middleCard)
        
        if !alertPlayers.isEmpty {
            
        }
        
        return .reveal(col: 0, row: 0)
    }
    
    func hasTwoFieldInCol(col: [RedactedFieldState], of number: Int) -> Bool {
        var revealedAndNumber = 0
        for field in col where .revealed(number) == field { revealedAndNumber += 1 }
        return revealedAndNumber == 2
    }
    
    func hasTwoFieldInCol(col: [RedactedFieldState]) -> Bool {
        var revealedAndNumber: [Int:Int] = [:]
        for field in col {
            if case .revealed(let number) = field {
                let occurences = revealedAndNumber[number]
                revealedAndNumber[number] = (occurences ?? 0) + 1
            }
        }
        
        return revealedAndNumber.contains { $0.1 == 2 }
    }
    
//    func getHighestCardNotInDoubleRow(field: PlayerField<RedactedFieldState>) -> (Int, Int) {
//        let allValues = field.fields.enumerated().compactMap { (colInd, col) in
//            if
//            col.enumerated().compactMap { (rowInd, element) in
//                if case .revealed(let number) = element {
//                    return (colInd, rowInd, number)
//                }
//                
//                return nil
//            }
//        }
//        
//        allValues.max {
//            
//        }
//    }
//    
    func playersWithImminentDestruction(state: RedactedGameState, for number: Int) -> [Int] {
        state.fields.enumerated().filter { (playerId, field) in
            hasFieldImminentDestruction(for: field, andNumber: number)
        }.map { $0.0 }
    }
    
    func hasFieldImminentDestruction(for playerField: PlayerField<RedactedFieldState>, andNumber number: Int) -> Bool {
        playerField.fields.first { col in
            hasTwoFieldInCol(col: col, of: number)
        } != nil
    }
}

extension DMatrix {
    mutating func mutate() -> Self {
        mapEach { value in
            if Int.random(in: 0...100) < 5 {
                return value + Double.random(in: (-0.3)...0.3)
            }
            
            return value
        }
    }
}

class MutatablePlayer: PlayerStrategy {
    var layer1: DMatrix
    var layer2: DMatrix
    var layer3: DMatrix
    
    var moves: [GameMove] = []
    var randomMoves = 0
    
    override init() {
        self.layer1 = DMatrix(20, 51) { _, _ in Double.random(in: -1...1) }
        self.layer2 = DMatrix(20, 20) { _, _ in Double.random(in: -1...1) }
        self.layer3 = DMatrix(3, 20) { _, _ in Double.random(in: -1...1) }
        
        super.init()
    }
    
    func mutate() {
        layer1 = layer1.mutate()
        layer2 = layer2.mutate()
        layer3 = layer3.mutate()
    }
    
    override func decision(state: RedactedGameState, ownPlayerId playerId: Int) -> GameMove {
        let inputVec = vectorizeState(state: state, playerId: playerId)
        let result = (layer3 * (layer2 * (layer1 * inputVec).fast()).fast()).fast().mapEach(sigmoid)
        
        let y = result.mapEach(sigmoid)
        
        let actionId = Int(y[0, 0] * 5)
        let col = Int(y[1, 0] * 4)
        let row = Int(y[2, 0] * 3)
        
        let move: GameMove = switch actionId {
        case 1: .end
        case 2: .drawTo(col: col, row: row)
        case 3: .reveal(col: col, row: row)
        case 4: .swapMiddle(col: col, row: row)
        default: .noMove
        }
        
        let validMoves = state.validMoves(for: playerId)
        if validMoves.contains(move) {
            moves.append(move)
            return move
        }
        
        let randomMove = validMoves[Int.random(in: 0..<validMoves.count)]
        moves.append(randomMove)
        randomMoves += 1
        return randomMove
    }
    
    func vectorizeState(state: RedactedGameState, playerId: Int) -> DMatrix {
        let input = state.vectorized + [Double(playerId), Double.random(in: 0...1)]
        return DMatrix(arrayLiteral: input).transpose()
    }
}

func main() {
    let mutablePlayer = MutatablePlayer()
    let gameLoop = GameLoop(players: [MutatablePlayer(), mutablePlayer, MutatablePlayer(), MutatablePlayer()])
    let scores = gameLoop.run()
    print(gameLoop.currentGameState.debugDescription)
    print("mutablePlayer.randomMoves = " + String(mutablePlayer.randomMoves))
    print("moves = ")
    dump(mutablePlayer.moves)
    print(scores)
}

main()
