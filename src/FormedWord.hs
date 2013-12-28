module FormedWord (wordsFormedMidGame, wordFormedFirstMove, mainWord, otherWords) where

  import Pos
  import Square
  import Tile
  import Board
  import ScrabbleError
  import Data.Sequence as Seq
  import Data.Map as Map
  import Control.Applicative
  import Control.Monad
  import Data.Foldable

  data FormedWords = FormedWords { mainWord :: FormedWord
                                  , otherWords :: [FormedWord]
                                  , board :: Board
                                  , placed :: Map Pos Square } deriving Show
  type FormedWord = Seq (Pos, Square)
  data Direction = Horizontal | Vertical deriving Eq

  {- 
     Returns the word formed by the first move on the board. The word must cover
     the star tile, and be linear.
   -}
  wordFormedFirstMove :: Board -> Map Pos Square -> Either ScrabbleError FormedWord
  wordFormedFirstMove board tiles = 
    if (starPos `Map.notMember` tiles) 
      then Left DoesNotIntersectCoverTheStarTile
      else mainWord <$> wordsFormed board tiles

  {- 
    Checks that a move made after the first move is legally placed on the board. A played word
    must be connected to a tile already on the board (or intersect tiles on the board), 
    and be formed linearly.
  -}
  wordsFormedMidGame :: Board -> Map Pos Square -> Either ScrabbleError FormedWords
  wordsFormedMidGame board tiles = wordsFormed board tiles >>= (\formed ->
    let FormedWords x xs _ _ = formed
    -- Check it connects to at least one other word on the board
    in if Seq.length x > Map.size tiles || not (Prelude.null xs)
           then Right $ FormedWords x xs board tiles
            else Left $ DoesNotConnectWithWord)

  wordsFormed :: Board -> Map Pos Square -> Either ScrabbleError FormedWords
  wordsFormed board tiles
    | Map.null tiles = Left NoTilesPlaced
    | not $ Map.null tiles = formedWords >>= (\formedWords -> 
    case formedWords of
      x : xs -> Right $ FormedWords x xs board tiles
      [] -> Left NoTilesPlaced
    )
    where
      formedWords = maybe (Left $ MisplacedLetter maxPos lastTile) (\direction -> 
          middleFirstWord direction >>= (\middleFirstWord -> 
                          let (midWord, square) = middleFirstWord
                          in let mainWord = preceding direction minPos >< midWord >< after direction maxPos
                          in Right $ mainWord : adjacentWords (swapDirection direction) ) ) getDirection

      preceding direction pos = case direction of
                                  Horizontal -> lettersLeft board pos
                                  Vertical -> lettersBelow board pos
      after direction pos =  case direction of
                                  Horizontal -> lettersRight board pos
                                  Vertical -> lettersAbove board pos

      (minPos, firstTile) = Map.findMin tiles
      (maxPos, lastTile) = Map.findMax tiles

      adjacentWords direction = Prelude.filter (\word -> Seq.length word > 1) $ Prelude.map (\(pos, square) ->
       (preceding direction pos |> (pos, square)) >< after direction pos) placedList

      middleFirstWord direction =
       case placedList of 
            x:[] -> Right (Seq.singleton x, minPos)
            (x:xs) -> 
              foldM (\(word, lastPos) (pos, square) -> 
                if (not $ stillOnPath lastPos pos direction)
                 then Left $ MisplacedLetter pos square
                  else 
                    if (isDirectlyAfter pos lastPos direction) then Right $ (word |> (pos, square), pos) else
                      let between = after direction lastPos in
                      if expectedLettersInbetween direction lastPos pos between
                       then Right $ ( word >< ( between |> (pos,square) ), pos)
                        else Left $ MisplacedLetter pos square


              ) (Seq.singleton x, minPos ) $ xs

      placedList = Map.toList tiles

      stillOnPath lastPos thisPos direction = (directionGetter direction thisPos) == directionGetter direction lastPos
      expectedLettersInbetween direction lastPos currentPos between =
       Seq.length between == directionGetter direction currentPos - directionGetter direction lastPos

      swapDirection direction = if direction == Horizontal then Vertical else Horizontal

      getDirection
        -- If only one tile is placed, we look for the first tile it connects with if any. If it connects with none, we return 'Nothing'
        | (minPos == maxPos) && not (Seq.null (lettersLeft board minPos))  || not (Seq.null (lettersRight board minPos)) = Just Horizontal
        | (minPos == maxPos) && not (Seq.null (lettersBelow board minPos)) || not (Seq.null (lettersAbove board minPos)) = Just Vertical
        | (xPos minPos) == (xPos maxPos) = Just Vertical
        | (yPos minPos) == (yPos maxPos) = Just Horizontal
        | otherwise = Nothing

      directionGetter direction pos = if direction == Horizontal then yPos pos else xPos pos

      isDirectlyAfter pos nextPos direction = 
        (directionGetter direction nextPos) == (directionGetter direction pos) + 1