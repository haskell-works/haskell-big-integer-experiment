{-# LANGUAGE StrictData #-}

import Control.Monad
import Data.Char
import Data.List
import Data.Map (Map)
import System.Environment
import System.Exit ( exitFailure, exitSuccess )

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set


main :: IO ()
main = do
    args <- getArgs
    case args of
        [x, y] -> runProgram (read x) (read y) Nothing
        [x, y, fname] -> runProgram (read x) (read y) $ Just fname
        _ -> usageExit


usageExit :: IO ()
usageExit = do
    progname <- getProgName
    putStrLn $ unlines
        [ ""
        , "Usage : " ++ progname ++ " x y <filename>"
        , ""
        , "where:"
        , "    x and y are numbers >= 2, x and y < 20 and x > y"
        , "    filename is optional (stdout will be used if missing)"
        , ""
        ]
    exitSuccess


runProgram :: Word -> Word -> Maybe String -> IO ()
runProgram x y mfname
    | x < y || x < 2 || y < 2 = do
        putStrLn $ "Error : x (" ++ show x ++ ") < y (" ++ show y ++ ")"
        usageExit
    | Just fname <- mfname =
        putStrLn $ "runProgram " ++ fname
    | otherwise =
        printTimes $ reorderOperations $ insertSums $ initializeProducts x y

-- -----------------------------------------------------------------------------
-- Implementation follows:

-- A source value. Can only be generated by a `LoadSource` operation and can
-- only be used as an input by a `TimesWord2` operation.
data Source
    = Source Word Char
    deriving (Eq, Ord, Show)


-- `Value`s (below) can be any of the following `ValueType`s.
-- This is used to make better decisions on how to operate on the values. For
-- instance, SumCarrys are guaranteed to be either `0` or `1` so that
-- `maxBound::Word` of them can be added together without any chance of a carry.
data ValueType
    = Product       -- A value generated by multiplying two Word values.
    | ProdCarry     -- The carry generated when two Word values are multiplied.
    | Sum           -- A value generated when twu values are added.
    | SumCarry      -- The carry generated when two Word values are added.
    deriving (Eq, Ord, Show)

-- A `Value` has a `ValueType` to
data Value
    = Value
        ValueType   -- How the value was generated.
        Word        -- The index
        Int         -- A unique value that in conjunction with the `ValueType`
                    -- and index is used to generate a unique name.
    deriving (Eq, Ord, Show)

vType :: Value -> ValueType
vType (Value t _ _) = t

vIndex :: Value -> Word
vIndex (Value _ w _) = w

vName :: Value -> Int
vName (Value _ _ n) = n


data Operation
    = LoadSource Source
    | TimesWord2 (Source, Source) (Value, Value)
    | PlusWord2 (Value, Value) (Value, Value)
    | PlusWord (Value, Value) Value
    | StoreValue Value
    deriving Show


opProvidesOutput :: Value -> Operation -> Bool
opProvidesOutput vt op =
    case op of
        LoadSource _ -> False
        TimesWord2 _ (v1, v2) -> v1 == vt || v2 == vt
        PlusWord2 _ (v1, v2) -> v1 == vt || v2 == vt
        PlusWord _ v -> v == vt
        StoreValue _ -> False

class Ppr a where
    ppr :: a -> String

instance Ppr Int where
    ppr i
        | i < 26 = [chr (i + ord 'a')]
        | otherwise =
                let (q, r) = i `quotRem` 26
                in ppr q ++ ppr r


instance Ppr Value where
    ppr (Value t w i) = ppr t ++ show w ++ ppr i

instance Ppr ValueType where
    ppr Product = "prod"
    ppr ProdCarry = "pc"
    ppr Sum = "sum"
    ppr SumCarry = "sc"

instance Ppr Source where
    ppr (Source w c) = c : show w

instance Ppr Operation where
    ppr (LoadSource (Source i c)) = [c] ++ show i ++ " <- indexWordArrayM " ++ [c] ++ "arr " ++ show i
    ppr (TimesWord2 (s0, s1) (co, po)) = "let (# " ++ ppr co ++ ", " ++ ppr po ++ " #) = timesWord2 " ++ ppr s0 ++ " " ++ ppr s1
    ppr (PlusWord2 (i1, i2) (co, so)) = "let (# " ++ ppr co ++ ", " ++ ppr so ++ " #) = plusWord2 " ++ ppr i1 ++ " " ++ ppr i2
    ppr (PlusWord (i1, i2) o) = "let " ++ ppr o ++ " = plusWord " ++ ppr i1 ++ " " ++ ppr i2
    ppr (StoreValue v) = "writeWordArray marr " ++ show (vIndex v) ++ " " ++ ppr v


-- | Compare Operations based on the Index of the primay output values. Using
-- this as the compare function passed to Data.List.sortBy should result in a
-- list of Operations which is still valid (as long as the list was valid
-- beforehand). Specifically, it groups all operations with lower value output
-- indices in front ot operations with higher value output indices. Ordering
-- within a given output index should remain unchanged.
opCompare :: Operation -> Operation -> Ordering
opCompare op1 op2 =
    compare (opIndex op1) (opIndex op2)
  where
    opIndex :: Operation -> Word
    opIndex (LoadSource (Source w _)) = w
    opIndex (TimesWord2 _ (_, v)) = vIndex v
    opIndex (PlusWord2 _ (_, v)) = vIndex v
    opIndex (PlusWord _ v) = vIndex v
    opIndex (StoreValue v) = vIndex v


data Times = Times
    { xv :: Word
    , yv :: Word
    , len :: Word
    , operations :: [Operation]
    , values :: Map Word [Value]
    , names :: Map Word [(ValueType, Int)]
    }
    deriving Show


displayTimes :: Times -> IO ()
displayTimes times = do
    putStrLn "-------------------------------------------------------------------------"
    mapM_ print $ operations times
    putStrLn "-------------------------------------------------------------------------"
    mapM_ (\ (k, v) -> unless (null v) (putStrLn $ show k ++ " : " ++ show v)) . Map.toList $ values times
    putStrLn "-------------------------------------------------------------------------"


timesEmpty :: Word -> Word -> Times
timesEmpty x y = Times x y (x + y) [] Map.empty Map.empty


insertResults :: Map Word [Value] -> Operation -> Map Word [Value]
insertResults vmap op =
    case op of
        TimesWord2 _ (v1, v2) -> addResult (++) v1 v2
        PlusWord2 _ (v1, v2) -> addResult appender v1 v2
        PlusWord _ v -> Map.insertWith appender (vIndex v) [v] vmap
        _ -> error $ "insertResults " ++ show op
  where
    appender xs ys = ys ++ xs
    addResult apf v1 v2 =
        Map.insertWith apf (vIndex v1) [v1]
            $ Map.insertWith apf (vIndex v2) [v2] vmap


insertNames :: Map Word [(ValueType, Int)] -> Operation -> Map Word [(ValueType, Int)]
insertNames vmap op =
    case op of
        TimesWord2 _ (v1, v2) -> addNames v1 v2
        PlusWord2 _ (v1, v2) -> addNames v1 v2
        PlusWord _ v -> Map.insertWith (++) (vIndex v) [(vType v, vName v)] vmap
        _ -> error $ "insertNames " ++ show op
  where
    vTypeName v = (vType v, vName v)
    addNames v1 v2 =
        Map.insertWith (++) (vIndex v1) [vTypeName v1]
            $ Map.insertWith (++) (vIndex v2) [vTypeName v2] vmap


-- Lookup existing value names to generate new unique nales for the outputs
-- of this operation.
fixName :: Times -> Operation -> Operation
fixName times op =
    case op of
        TimesWord2 x (v1, v2) -> TimesWord2 x (fixValName v1, fixValName v2)
        PlusWord2 x (v1, v2) -> PlusWord2 x (fixValName v1, fixValName v2)
        PlusWord x v -> PlusWord x (fixValName v)
        _ -> error $ "fixName " ++ show op
  where
    newName :: ValueType -> Word -> [(ValueType, Int)] -> Value
    newName t i xs =
        case map snd (filter (\vt -> fst vt == t) xs) of
            [] -> Value t i 0
            ys -> Value t i $ succ (maximum ys)
    fixValName :: Value -> Value
    fixValName (Value t i 0) =
        maybe (Value t i 0) (newName t i) $ Map.lookup i (names times)
    fixValName v = v


appendOp :: Operation -> Times -> Times
appendOp origOp times =
    let op = fixName times origOp
    in times
        { operations = operations times ++ [op]
        , values = insertResults (values times) op
        , names = insertNames (names times) op
        }


insertOp :: Operation -> Times -> Times
insertOp origOp times =
    let op = fixName times origOp
    in times
        { operations = operations times
        , values = insertResults (values times) op
        , names = insertNames (names times) op
        }


-- Given an `n` and `m`, calling `initializeProducts n m` sets up the `Times`
-- data structure to do an `n * m` multipication.
initializeProducts :: Word -> Word -> Times
initializeProducts left right =
    insertLoads $ foldl' generate (timesEmpty left right) prodIndices
  where
    generate times (x, y) =
        let idx = x + y
            prod = Value Product idx 0
            carry = Value ProdCarry (idx + 1) 0
        in appendOp (TimesWord2 (Source x 'x', Source y 'y') (carry, prod)) times

    prodIndices :: [(Word, Word)]
    prodIndices =
        let ys = [0 .. left - 1]
            compf (a, b) (c, d) =
                case compare (a + b) (c + d) of
                    EQ -> compare a b
                    cx -> cx
        in sortBy compf $ concatMap (zip ys . replicate (fromIntegral left)) [0 .. right - 1]


insertLoads :: Times -> Times
insertLoads times =
    times { operations = ins Set.empty Set.empty (operations times) }
  where
    ins xload yload (op@(TimesWord2 (x, y) _):ops) =
        case (Set.member x xload, Set.member y yload) of
            (True, True) -> op : ins xload yload ops
            (True, False) -> LoadSource y : op : ins xload (Set.insert y yload) ops
            (False, True) -> LoadSource x : op : ins (Set.insert x xload) yload ops
            (False, False) -> LoadSource x : LoadSource y : op : ins (Set.insert x xload) (Set.insert y yload) ops
    ins xload yload (op:ops) = op : ins xload yload ops
    ins _ _ [] = []


insertSums :: Times -> Times
insertSums times =
    foldl' (flip insertIndexSums) times [ 0 .. (2 + maximum (Map.keys (values times))) ]
  where
    getIndexVals :: Word -> Times -> (Times, [Value])
    getIndexVals i txs =
        let vmap = values txs
            getVals vals =
                case splitAt 2 vals of
                    ([a], []) -> (txs { values = Map.insert i [] vmap } , [a])
                    ([a, b], rest) -> (txs { values = Map.insert i rest vmap } , [a, b])
                    _ -> (txs, [])
        in maybe (txs, []) getVals $ Map.lookup i vmap

    insertIndexSums :: Word -> Times -> Times
    insertIndexSums index txs =
        case getIndexVals index txs of
            (newtxs, [a, b]) -> insertIndexSums index $ appendOp (makeSum (len txs - 1) a b) newtxs
            (newtxs, [a]) -> newtxs { operations = operations newtxs ++ [StoreValue a] }
            (_, _) -> txs


makeSum :: Word -> Value -> Value -> Operation
makeSum maxIndex v1 v2 =
    case (v1, v2) of
        -- Sums that can produce a carry.
        (Value Product i _, Value Product _ _) ->
            PlusWord2 (v1, v2) (Value SumCarry (i + 1) 0, Value Sum i 0)
        (Value ProdCarry i _, Value Sum _ _) ->
            PlusWord2 (v1, v2) (Value SumCarry (i + 1) 0, Value Sum i 0)
        (Value Product i _, Value ProdCarry _ _) ->
            PlusWord2 (v1, v2) (Value SumCarry (i + 1) 0, Value Sum i 0)
        (Value ProdCarry i _, Value ProdCarry _ _) ->
            PlusWord2 (v1, v2) (Value SumCarry (i + 1) 0, Value Sum i 0)

        (Value Sum _ _, Value SumCarry i _) -> lastPlusWord i
        (Value SumCarry i _, Value Sum _ _) -> lastPlusWord i
        (Value Sum i _, Value Sum _ _) -> lastPlusWord i


        -- Sums that *will not* produce a carry.
        (Value ProdCarry i _, Value SumCarry _ _) ->
            PlusWord (v1, v2) (Value Sum i 0)
        (Value SumCarry i _, Value SumCarry _ _) ->
            PlusWord (v1, v2) (Value Sum i 0)

        x -> error $ "makeSum " ++ show x
  where
    lastPlusWord i =
        if i >= maxIndex
            then PlusWord (v1, v2) (Value Sum i 0)
            else PlusWord2 (v1, v2) (Value SumCarry (i + 1) 0, Value Sum i 0)


-- Optimize the order of operations. For example, as soon as a final output
-- value is calculated, it should be written to the output array.
reorderOperations :: Times -> Times
reorderOperations times = times { operations = sortBy opCompare $ operations times }


-- Validation of the final list of operations.
validateValueUsage :: Times -> IO ()
validateValueUsage times = do
    results <- sequence
                [ valuesAreEmpty
                , valuesAreUniqueAndUsedOnce $ extractValues (operations times)
                , validateOperationOrdering $ operations times
                ]
    when (or results) $ do
        putStrLn "Terminating"
        exitFailure
    putStrLn "Looks good to me!"
  where
    valuesAreEmpty =
        let elems = concat . Map.elems $ values times
        in if null elems
            then return False
            else do
                putStrLn $ "validateValueUsage found unused values : " ++ show elems
                return True

    valuesAreUniqueAndUsedOnce (outvals, invals) = do
        let out_ok = length (nub outvals) == length outvals
            in_ok = length (nub invals) == length invals
            unused_in = filter (`notElem` outvals) invals
            unused_out = filter (`notElem` invals) outvals

        unless in_ok $
            putStrLn $ "validateValueUsage found duplicate inputs : " ++ show invals ++ "\n"
        unless out_ok $
            putStrLn $ "validateValueUsage found duplicate outputs : " ++ show outvals ++ "\n"

        unless (null unused_in) $
            putStrLn $ "validateValueUsage unused inputs : " ++ show unused_in ++ "\n"
        unless (null unused_out) $
            putStrLn $ "validateValueUsage unused outputs : " ++ show unused_out ++ "\n"

        return (in_ok && out_ok && not (null unused_in) && not (null unused_out))

    setInsert2 (a, b) = Set.insert a . Set.insert b

    setMembers2 (a, b) set = Set.member a set && Set.member b set

    opCheckArgs (ok, vs) op =
        case op of
            LoadSource _ -> return (ok, vs)
            TimesWord2 _ outs -> return (ok, setInsert2 outs vs)
            PlusWord2 ins outs -> return (ok && setMembers2 ins vs, setInsert2 outs vs)
            PlusWord ins out -> return (ok && setMembers2 ins vs, Set.insert out vs)
            StoreValue _ -> return (ok, vs)

    validateOperationOrdering oplist =
        fst <$> foldM opCheckArgs (False, Set.empty) oplist

extractValues :: [Operation] -> ([Value], [Value])
extractValues =
    sortLR . foldl' extract ([], [])
  where
    sortLR (a, b) = (sort a, sort b)
    extract (ins, outs) op =
        case op of
            LoadSource _ -> (ins, outs)
            TimesWord2 _ (o1, o2) -> (ins, o1 : o2 : outs)
            PlusWord2 (i1, i2) (o1, o2) -> (i1 : i2 : ins, o1 : o2 : outs)
            PlusWord (i1, i2) o -> (i1 : i2 : ins, o : outs)
            StoreValue i -> (i : ins, outs)


pprTimes :: Times -> [String]
pprTimes times =
    [ ""
    , "{-# INLINE " ++ name ++ " #-}"
    , name ++ " :: WordArray -> WordArray -> Natural"
    , name ++ " !xarr !yarr ="
    , "    runStrictPrim $ do"
    , "        marr <- newWordArray " ++ show maxlen
    ]
    ++ map (indent8 . ppr) ( operations times)
    ++ map indent8
        [ "narr <- unsafeFreezeWordArray marr"
        , "let !len = " ++ show (maxlen - 1) ++ " + boxInt# (neWord# (unboxWord " ++ lastCarry ++ ") 0##)"
        , "return $! Natural len narr"
        , ""
        ]
  where
    name = "timesNat" ++ show (xv times) ++ "x" ++ show (yv times)
    indent8 s = "        " ++ s
    maxlen = xv times + yv times
    lastCarry =
        case last (operations times) of
            StoreValue v -> ppr v
            x -> error $ "lastCarry " ++ show x


printTimes :: Times -> IO ()
printTimes = mapM_ putStrLn . pprTimes
