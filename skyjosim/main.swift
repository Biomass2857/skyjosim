import Foundation
import Dispatch

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
    
    func reveal(col: Int, row: Int) -> (Self, [Int]) where FieldStateType == FieldState {
        guard case .unrevealed(let number) = fields[col][row] else {
            fatalError("wrong move")
        }
        
        var tempFields = fields
        tempFields[col][row] = .revealed(number)
        if tempFields[col].allSatisfy({ $0 == .revealed(number) }) {
            tempFields[col] = tempFields[col].map { _ in .gone }
            let discarded = tempFields[col].map { _ in number }
            return (PlayerField(fields: tempFields), discarded)
        }
        
        return (PlayerField(fields: tempFields), [])
    }
    
    func swapInto(col: Int, row: Int, card: Int) -> (Self, [Int]) where FieldStateType == FieldState {
        var tempFields = fields
        switch fields[col][row] {
        case .gone: fatalError("wrong move")
        case .revealed(let number), .unrevealed(let number):
            tempFields[col][row] = .revealed(card)
            if tempFields[col].allSatisfy({ $0 == .revealed(card) }) {
                tempFields[col] = tempFields[col].map { _ in .gone }
                let discarded = tempFields[col].map { _ in card }
                return (.init(fields: tempFields), [number] + discarded)
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
    let offStack: [Int]
    let stack: [Int]
    let fields: [PlayerField<FieldState>]
    let endsAt: Int?
    
    var playerHasEnded: Bool {
        endsAt != nil
    }
    
    var scores: [Int:Int] {
        var scores = Dictionary(uniqueKeysWithValues: fields.correctEnum().map { index, field in
            return (index, field.sum())
        })
        
        if let endsAt = endsAt,
           let minimumScore = scores.filter({ $0.key != endsAt }).values.min(),
           let score = scores[endsAt],
           score >= minimumScore {
            scores[endsAt] = 2 * score
        }
        
        return scores
    }
    
    func hasEnded(at playerId: Int) -> Bool {
        endsAt == playerId
    }
    
    func validMoves(for playerId: Int) -> [GameMove] {
        if endsAt == playerId {
            return []
        }
        
        let canEndMoves: [GameMove] = !playerHasEnded ? [.end] : []
        
        return canEndMoves + PlayerField<FieldState>.fieldTuples.flatMap { row, col -> [GameMove] in
            return switch fields[playerId].fields[col][row] {
            case .gone: []
            case .unrevealed(_): [.drawTo(col: col, row: row), .swapMiddle(col: col, row: row), .reveal(col: col, row: row)]
            case .revealed(_): [.drawTo(col: col, row: row), .swapMiddle(col: col, row: row)]
            }
        }
    }
    
    func refillStackIfNeeded() -> (newStack: [Int], newOffStack: [Int]) {
        guard stack.isEmpty else {
            return (stack, offStack)
        }
        
        return (offStack.shuffled(), [])
    }
    
    func applying(move: GameMove, playerId: Int) -> GameState {
        let field = fields[playerId]
        switch move {
        case .reveal(let col, let row):
            var (newField, discarded) = field.reveal(col: col, row: row)
            var tempFields = fields
            tempFields[playerId] = newField
            
            let newMiddleCard = discarded.count == 0 ? middleCard : discarded.removeLast()
            
            let newOffStack = offStack + discarded
            
            return .init(
                middleCard: newMiddleCard,
                offStack: newOffStack,
                stack: stack,
                fields: tempFields,
                endsAt: endsAt
            )
            
        case .swapMiddle(let col, let row):
            var (newField, discardedCards) = field.swapInto(col: col, row: row, card: middleCard)
            var tempFields = fields
            tempFields[playerId] = newField
            let newMiddleCard = discardedCards.removeLast()
            let newOffStack = offStack + discardedCards
            
            return .init(
                middleCard: newMiddleCard,
                offStack: newOffStack,
                stack: stack,
                fields: tempFields,
                endsAt: endsAt
            )
            
        case .drawTo(let col, let row):
            var (currentStack, currentOffStack) = refillStackIfNeeded()
            let drawnCard = currentStack.removeLast()
            var (newField, discarded) = field.swapInto(col: col, row: row, card: drawnCard)
            var tempFields = fields
            tempFields[playerId] = newField
            
            let newMiddleCard = discarded.removeLast()
            let newOffStack = currentOffStack + [middleCard] + discarded
            
            return .init(
                middleCard: newMiddleCard,
                offStack: newOffStack,
                stack: currentStack,
                fields: tempFields,
                endsAt: endsAt
            )
        
        case .end:
            guard endsAt == nil else {
                fatalError("only one can finish")
            }
            
            return .init(
                middleCard: middleCard,
                offStack: offStack,
                stack: stack,
                fields: fields,
                endsAt: playerId
            )
        }
    }
    
    func redacted() -> RedactedGameState {
        .init(
            middleCard: middleCard,
            fields: fields.map { $0.redacted() },
            endsAt: endsAt
        )
    }
    
    var debugDescription: String {
        var s = "middleCard: \(middleCard)\n"
        s += "stack: \(stack)\n"
        for (index, player) in fields.correctEnum() {
            s += "player: \(index)\n"
            s += player.debugDescription + "\n"
        }
        return s
    }
}

struct RedactedGameState: CustomDebugStringConvertible {
    let middleCard: Int
    let fields: [PlayerField<RedactedFieldState>]
    let endsAt: Int?
    
    var playerHasEnded: Bool {
        endsAt != nil
    }
    
    func hasEnded(at playerId: Int) -> Bool {
        endsAt == playerId
    }
    
    var debugDescription: String {
        var s = "middleCard: \(middleCard)\n"
        for (index, player) in fields.correctEnum() {
            s += "player: \(index)\n"
            s += player.debugDescription + "\n"
        }
        return s
    }
    
    func validMoves(for playerId: Int) -> [GameMove] {
        if endsAt == playerId {
            return []
        }
        
        let canEndMoves: [GameMove] = !playerHasEnded ? [.end] : []
        
        return canEndMoves + PlayerField<FieldState>.fieldTuples.flatMap { row, col -> [GameMove] in
            return switch fields[playerId].fields[col][row] {
            case .gone: []
            case .unrevealed: [.drawTo(col: col, row: row), .swapMiddle(col: col, row: row), .reveal(col: col, row: row)]
            case .revealed(_): [.drawTo(col: col, row: row), .swapMiddle(col: col, row: row)]
            }
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
}

protocol PlayerStrategy {
    func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove
}

extension Array {
    @discardableResult
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
    
    init(players: [PlayerStrategy]) {
        self.players = players
        
        var shuffledCards = cards.shuffled()
        
        let middleCard = shuffledCards.popLast()!
        
        let fields: [PlayerField<FieldState>] = Array(0...3).map { playerId in
            return .init(fields: shuffledCards.popLast(12).map { .unrevealed($0 )})
        }
        
        self.currentGameState = .init(
            middleCard: middleCard,
            offStack: [],
            stack: shuffledCards,
            fields: fields,
            endsAt: nil
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
            offStack: [],
            stack: shuffledCards,
            fields: fields,
            endsAt: nil
        )
    }
    
    func step() {
        defer {
            currentPlayer = (currentPlayer + 1) % players.count
        }
        
        if currentGameState.hasEnded(at: currentPlayer) {
            debugPrint("game ended")
            return
        }
        
        let strategy = players[currentPlayer]
        
        let move = strategy.decision(state: currentGameState.redacted(), ownPlayerId: currentPlayer)
        
        currentGameState = currentGameState.applying(move: move, playerId: currentPlayer)
    }
    
    func run() -> [Int:Int] {
        initialize()
        while true {
            if currentGameState.hasEnded(at: currentPlayer) {
                break
            }
            
            step()
        }
        
        return currentGameState.scores
    }
    
//    func playerWon(scores: [Int:Int]) -> Int {
//        scores.min { tupleA, tupleB in
//            tupleA.1 < tupleB.1
//        }?.0 ?? -1
//    }
//    
//    func evaluate() -> Int {
//        let scores = run()
//        return playerWon(scores: scores)
//    }
}

class EndPlayer: PlayerStrategy {
    var move = 0
    let max = 12
    func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove {
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
    func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove {
        move += 1
        return .swapMiddle(col: 0, row: (move - 1) % 3)
    }
}

class TomPlayer: PlayerStrategy {
    func decision(state: RedactedGameState, ownPlayerId: Int) -> GameMove {
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
        state.fields.correctEnum().filter { (playerId, field) in
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

class MutatablePlayer: PlayerStrategy, Codable {
    var layer1: DMatrix
    var layer2: DMatrix
    var layer3: DMatrix
    
    init(
        layer1: DMatrix = DMatrix(20, 51) { _, _ in Double.random(in: -1...1) },
        layer2: DMatrix = DMatrix(20, 20) { _, _ in Double.random(in: -1...1) },
        layer3: DMatrix = DMatrix(3, 20) { _, _ in Double.random(in: -1...1) }
    ) {
        self.layer1 = layer1
        self.layer2 = layer2
        self.layer3 = layer3
    }
    
    func mutating() -> MutatablePlayer {
        return .init(
            layer1: layer1.mutate(),
            layer2: layer2.mutate(),
            layer3: layer3.mutate()
        )
    }
    
    func decision(state: RedactedGameState, ownPlayerId playerId: Int) -> GameMove {
        let inputVec = vectorizeState(state: state, playerId: playerId)
        let result = (layer3 * (layer2 * (layer1 * inputVec).fast()).fast()).fast().mapEach(sigmoid)
        
        let y = result.mapEach(sigmoid)
        
        let actionId = Int(y[0, 0] * 4)
        let col = Int(y[1, 0] * 4)
        let row = Int(y[2, 0] * 3)
        
        let move: GameMove = switch actionId {
        case 0: .end
        case 1: .drawTo(col: col, row: row)
        case 2: .reveal(col: col, row: row)
        case 3: .swapMiddle(col: col, row: row)
        default: preconditionFailure("switch should be exhaustive because of sigmoid properties")
        }
        
        let validMoves = state.validMoves(for: playerId)
        if validMoves.contains(move) {
            return move
        }
        
        let randomMove = validMoves[Int.random(in: 0..<validMoves.count)]
        return randomMove
    }
    
    func vectorizeState(state: RedactedGameState, playerId: Int) -> DMatrix {
        let input = state.vectorized + [Double(playerId), Double.random(in: 0...1)]
        return DMatrix(arrayLiteral: input).transpose()
    }
}

struct ScorablePlayer: Codable {
    let strategy: MutatablePlayer
    var accumRoundsTopK: Int
    var roundsTopK: Int
    var currentScore: Int
    
    var totalTopK: Int {
        accumRoundsTopK + roundsTopK
    }
}

struct PlayerSample: Codable {
    var players: [ScorablePlayer]
}

func fileURL(filename: String) -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
}

func tryLoadState<S: Decodable>(filename: String) -> S? {
    let url = fileURL(filename: filename)
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let object = try decoder.decode(S.self, from: data)
        return object
    } catch {
        debugPrint("Error loading file: \(error)")
        return nil
    }
}

func dumpState<S: Encodable>(filename: String, object: S) {
    let url = fileURL(filename: filename)
    do {
        let data = try JSONEncoder().encode(object)
        try data.write(to: url)
    } catch {
        fatalError("couldnt save file \(error)")
    }
}

//func registerSignals(onSignal: @escaping () -> Void) {
//    signal(SIGINT, SIG_IGN)
//    signal(SIGTERM, SIG_IGN)
//    
//    let sigIntSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
//    sigIntSrc.setEventHandler {
//        onSignal()
//        exit(0)
//    }
//    
//    sigIntSrc.resume()
//    
//    let sigTermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
//    sigTermSrc.setEventHandler {
//        onSignal()
//        exit(0)
//    }
//    
//    sigTermSrc.resume()
//}

func main() async {
    let playerCount = 100
    let gameCount = 300
    let parallelGames = playerCount / 4
    let topK = 20
    let maxGens = 3
    
    var records: [Int] = []
    
    var players: [ScorablePlayer] = Array(0..<playerCount).map { _ in
        .init(strategy: MutatablePlayer(), accumRoundsTopK: 0, roundsTopK: 0, currentScore: 0)
    }
//    
//    registerSignals {
//        let sample = PlayerSample(players: players)
//        dumpState(filename: "players.txt", object: sample)
//        debugPrint("saved players")
//    }
//    
    if let sample: PlayerSample = tryLoadState(filename: "players.txt") {
        players = sample.players
        debugPrint("loaded players")
    }
    
    for gen in 0..<maxGens {
        for game in 0..<gameCount {
            players = players.shuffled()
            
            var tasks: [Task<(Int, [Int: Int]), Never>] = []
            for parallelGameId in 0..<parallelGames {
                let startPlayerIndex = 4 * parallelGameId
                let endPlayerIndex = 4 * (parallelGameId + 1)
                let playerList = players[startPlayerIndex..<endPlayerIndex].map { $0.strategy }
                tasks.append(Task {
                    let gameLoop = GameLoop(players: playerList)
                    let scores = gameLoop.run()
                    return (parallelGameId, scores)
                })
            }
            
            for task in tasks {
                let (gameId, scores) = await task.value
                scores.forEach { id, score in
                    players[4 * gameId + id].currentScore += score
                }
            }
        }
        
        let scores = players.map { $0.currentScore }
        let minimum = scores.min()!
        let maximum = scores.max()!
        debugPrint("gen \(gen) current scores of players: \(minimum) - \(maximum)")
        
        records.append(players.map { $0.currentScore }.min()!)
        
        players = players.sorted { $0.currentScore < $1.currentScore }
        
        debugPrint("rounds survived: ")
        dump(
            players
                .sorted { $0.totalTopK < $1.totalTopK }
                .map { "a = \($0.accumRoundsTopK); b = \($0.roundsTopK)" }
        )
        
        let deletePlayerAmount = playerCount - topK
        players.popLast(deletePlayerAmount)
        
        for i in 0..<players.count {
            players[i].roundsTopK += 1
        }
        
        for index in players.indices {
            players[index].currentScore = 0
        }
        
        players += Array(0..<deletePlayerAmount).map { _ in
            let randomAncestorIndex = Int.random(in: 0..<topK)
            let ancestor = players[randomAncestorIndex]
            
            return .init(
                strategy: ancestor.strategy.mutating(),
                accumRoundsTopK: ancestor.totalTopK,
                roundsTopK: 0,
                currentScore: 0
            )
        }
    }
    
    let sample = PlayerSample(players: players)
    dumpState(filename: "players.txt", object: sample)
    debugPrint("saved players")
    
    debugPrint("record trace")
    debugPrint(records)
}

Task {
    await main()
}

while true {}
//dispatchMain()
