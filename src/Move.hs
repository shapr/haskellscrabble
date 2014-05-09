module Move (makeMove, Move (PlaceTiles, Exchange, Pass), GameTransition(MoveTransition, ExchangeTransition, PassTransition), restoreGame, newGame) where

  import ScrabbleError
  import FormedWord
  import Control.Monad
  import Control.Applicative
  import Data.Maybe
  import Game
  import Player
  import Data.Map as Map
  import Pos
  import Tile
  import LetterBag
  import Board
  import Dictionary
  import Data.Foldable
  import Game.Internal
  import Game
  import qualified Data.List.NonEmpty as NE
  import qualified Data.Traversable as T

  data GameTransition = MoveTransition Game FormedWords | ExchangeTransition Game Player Player | PassTransition Game

  makeMove :: Game -> Move -> Either ScrabbleError GameTransition
  makeMove game move = flip addMoveToHistory move <$> gameTransition
    where
      gameTransition = case move of
        PlaceTiles placed -> makeBoardMove game placed
        Exchange exchanged -> exchangeMove game exchanged
        Pass -> passMove game

  {- 
    Restores a game from a list of moves. The game must be set up in the way the original game was set up
    (including the letter bag constructed with the same tiles and random generator, dictionary and the list of players
    in the original order.)
 
    If the game is not set up as it was originally, this function will return a scrabble error with the move which was invalid
    with the given state. For example, if the original players are not ordered in the correct way then the player will not have
    the required tiles to make the move.
  -}
  restoreGame :: Game -> NE.NonEmpty Move -> Either ScrabbleError (NE.NonEmpty GameTransition)
  restoreGame game (mv NE.:| moves) = T.sequence $ NE.scanl nextMove (makeMove game mv) moves 
    where
      nextMove transition mv = transition >>= \success -> makeMove (newGame success) mv
 
  newGame :: GameTransition -> Game
  newGame (MoveTransition game _) = game
  newGame (ExchangeTransition game _ _) = game
  newGame (PassTransition game) = game

  addMoveToHistory :: GameTransition -> Move -> GameTransition
  addMoveToHistory (MoveTransition game formedWords) move = MoveTransition (updateHistory game move) formedWords
  addMoveToHistory (ExchangeTransition game oldPlayer newPlayer ) move = ExchangeTransition (updateHistory game move) oldPlayer newPlayer
  addMoveToHistory (PassTransition game) move = PassTransition (updateHistory game move)

  makeBoardMove :: Game -> Map Pos Tile -> Either ScrabbleError GameTransition
  makeBoardMove game placed 
    | (not $ gameStatus game == InProgress) = Left GameNotInProgress
    | otherwise = 
        do
          formed <- formedWords
          (overallScore, _) <- scoresIfWordsLegal dict formed
          board <- newBoard currentBoard placed 
          player <- removeLettersandGiveScore player playedTiles overallScore

          if hasEmptyRack player && (bagSize letterBag == 0)
           then
            do
              let (newPlayer, updatedGame) = updateGame game player board letterBag
              return $ MoveTransition (updatedGame {gameStatus = ToFinalise}) formed
            else
              do
                let (newPlayer, newBag) = updatePlayerRackAndBag player letterBag (Map.size placed)
                let (nextPlayer, updatedGame) = updateGame game newPlayer board newBag
                return $ MoveTransition updatedGame formed

      where
        player = currentPlayer game
        playedTiles = Map.elems placed
        currentBoard = board game
        moveNo = moveNumber game
        dict = dictionary game
        letterBag = bag game

        formedWords = if (moveNo == 1)
         then wordFormedFirstMove currentBoard placed 
         else wordsFormedMidGame currentBoard placed

  exchangeMove :: Game -> [Tile] -> Either ScrabbleError GameTransition
  exchangeMove game tiles 
    | not (gameStatus game == InProgress) = Left GameNotInProgress
    | otherwise = 
        let exchangeOutcome = exchangeLetters (bag game) tiles
        in case exchangeOutcome of
          Nothing -> Left CannotExchangeWhenNoLettersInBag
          Just (givenTiles, newBag) -> 
              let newPlayer = exchange player tiles givenTiles
              in maybe (Left $ PlayerCannotExchange (rack player) tiles) (\exchangedPlayer ->
                        let (nextPlayer, newGame) = updateGame game exchangedPlayer (board game) newBag
                        in Right $ ExchangeTransition newGame player exchangedPlayer) newPlayer
    where
      player = currentPlayer game

  passMove :: Game -> Either ScrabbleError GameTransition
  passMove game
    | not (gameStatus game == InProgress) = Left GameNotInProgress
    | otherwise = Right $ let (_, newGame) = pass game in PassTransition $ newGame {gameStatus = newStatus}
      where
        numPasses = passes game
        newStatus = if numPasses == ((numberOfPlayers game) * 2) then ToFinalise else InProgress

  finaliseGame :: Game -> Game
  finaliseGame game
    | (gameStatus game == Finished) = game
    | otherwise = game {player1 = play1, player2 = play2, optionalPlayers = optional, gameStatus = Finished}
      where
        unplayedValues = Prelude.sum $ Prelude.map tileValues allPlayers
        allPlayers = getPlayers game

        play1 = finalisePlayer (player1 game)
        play2 = finalisePlayer (player2 game)
        optional = optionalPlayers game >>= (\(player3, maybePlayer4) ->
            Just (finalisePlayer player3, (\play4 -> finalisePlayer play4) <$> maybePlayer4 ) )

        finalisePlayer player = if hasEmptyRack player then increaseScore player unplayedValues
          else reduceScore player (tileValues player) 

  updatePlayerRackAndBag :: Player -> LetterBag -> Int -> (Player, LetterBag)
  updatePlayerRackAndBag player letterBag numPlayed =
    if tilesInBag == 0 
      then (player, letterBag)
      else
        if (tilesInBag >= numPlayed)
          then maybe (player, letterBag) (\(taken, newBag) -> 
            (giveTiles player taken, newBag)) $ takeLetters letterBag numPlayed
            else maybe (player, letterBag) (\(taken, newBag) -> 
              (giveTiles player taken, newBag)) $ takeLetters letterBag tilesInBag
    
    where
      tilesInBag = bagSize letterBag

  newBoard :: Board -> Map Pos Tile -> Either ScrabbleError Board
  newBoard board placed = foldM (\board (pos, tile) -> newBoardIfUnoccupied board pos tile) board $ Map.toList placed
    where
      newBoardIfUnoccupied board pos tile = maybe (Left $ PlacedTileOnOccupiedSquare pos tile) Right $ placeTile board tile pos

  
  removeLettersandGiveScore :: Player -> [Tile] -> Int -> Either ScrabbleError Player
  removeLettersandGiveScore player tiles justScored = 
    let newPlayer = removePlayedTiles player tiles 
    in case newPlayer of
      Nothing -> Left $ PlayerCannotPlace (rack player) tiles
      Just (playerUpdatedRack) -> Right $ increaseScore playerUpdatedRack justScored
    

  scoresIfWordsLegal :: Dictionary -> FormedWords -> Either ScrabbleError (Int, [(String, Int)])
  scoresIfWordsLegal dict formedWords = 
    let strings = wordStrings formedWords
    in case invalidWords dict strings of
      (x:xs) -> Left $ WordsNotInDictionary (x:xs)
      otherwise -> Right $ wordsWithScores formedWords
