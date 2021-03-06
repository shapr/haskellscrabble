module Wordify.Rules.Game.Internal (updateGame, Game(Game),
     GameStatus(InProgress, Finished),
      moveNumber,
      playerNumber,
      currentPlayer,
      passes,
      nextPlayer,
      player1,
      player2,
      optionalPlayers,
      gameStatus,
      board,
      bag,
      pass,
      dictionary,
      updateHistory,
      Move(PlaceTiles, Exchange, Pass),
      History(History),
      history) where

  import Wordify.Rules.Player
  import Wordify.Rules.Board
  import Wordify.Rules.LetterBag
  import Wordify.Rules.Dictionary
  import Control.Applicative
  import Data.Map
  import Wordify.Rules.Pos
  import Wordify.Rules.Tile
  import Data.Sequence

  data Move = PlaceTiles (Map Pos Tile) | Exchange [Tile] | Pass deriving (Eq, Show)

  data History = History LetterBag (Seq Move) deriving (Eq, Show)

  data GameStatus = InProgress | Finished deriving (Eq, Show)

  data Game = Game { player1 :: Player
                     , player2 :: Player
                     , optionalPlayers :: Maybe (Player, Maybe Player)
                     , board :: Board
                     , bag :: LetterBag
                     , dictionary :: Dictionary 
                     , currentPlayer :: Player
                     , playerNumber :: Int
                     , moveNumber :: Int
                     , passes :: Int
                     , gameStatus :: GameStatus
                     , history :: History }

  {-
    Updates the game with the new board and letter bag state, and the last player to play's state after replacing their played
    tiles with new tiles from the letter bag. 

    Yields the next game state.
  -}
  updateGame :: Game -> Player -> Board -> LetterBag -> Game
  updateGame game player newBoard newBag = 
   updatedPlayerGame {board = newBoard, bag = newBag, currentPlayer = newPlayer, playerNumber = newPlayerNum, moveNumber = succ moveNo, passes = 0}
    where
      updatedPlayerGame = updateCurrentPlayer game player
      (newPlayerNum, newPlayer) = nextPlayer game
      moveNo = moveNumber game

  updateCurrentPlayer :: Game -> Player -> Game
  updateCurrentPlayer game player =
    case playing of
      1 -> game {player1 = player}
      2 -> game {player2 = player}
      3 -> game {optionalPlayers = (\(_, player4) -> (player, player4)) <$> maybePlayers }
      _ -> game {optionalPlayers = (\(player3, _) -> (player3, (Just player))) <$> maybePlayers  }

    where
      playing = playerNumber game
      maybePlayers = optionalPlayers game

  {- Returns the next player to play. If there are optional players, loops back round to 'player 1' where appropriate. -}
  nextPlayer :: Game -> (Int, Player)
  nextPlayer game 
    | (playing == 1) = (2, playr2)
    | (playing == 2 || playing == 3) =
     maybe ( (1, playr1) ) (\(player3, player4) -> 
      if (playing == 2) then (3, player3 )
      else 
        case player4 of
          Just playr4 -> (4, playr4)
          Nothing -> (1, playr1)
        ) $ maybePlayers
    | otherwise = (1, playr1)

    where
      playing = playerNumber game
      playr2 = player2 game
      playr1 = player1 game
      maybePlayers = optionalPlayers game


  pass :: Game -> Game
  pass game =  game {moveNumber = succ moveNo, playerNumber = playerNo, currentPlayer = player, passes = succ numPasses}
    where
      (playerNo, player) = nextPlayer game
      numPasses = passes game
      moveNo = moveNumber game

  updateHistory :: Game -> Move -> Game
  updateHistory game move = game {history = History originalBag (moveList |> move) }
    where
      History originalBag moveList = history game
