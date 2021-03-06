{-# LANGUAGE CPP, MagicHash, ScopedTypeVariables #-}

import Prelude hiding (Integer)

import Control.Exception (SomeException, catch)
import Data.List (nub, sort)
import System.Environment
import System.IO.Unsafe (unsafePerformIO)

import qualified Criterion.Main as C
import qualified System.Random as R

import Check.Bench1 as Bench1
import Check.Bench2 as Bench2
import Check.Bench3 as Bench3
import Check.Bench4 as Bench4
import Check.BenchG as BenchG


-- BigTimes and HugeTimes? pidigits?

main :: IO ()
main = do
    benchmarks <- findBenchmarks
    C.defaultMain benchmarks


--------------------------------------------------------------------------------
-- The benchmarks.

addSmallBench :: (Int, Int, Int) -> C.Benchmark
addSmallBench addSmallParam =
    C.bgroup "Small Integer addition and subtraction"
            [ C.bench "GMP"     $ C.whnf BenchG.addSmallLoop addSmallParam
            , C.bench "New1"    $ C.whnf Bench1.addSmallLoop addSmallParam
            , C.bench "New2"    $ C.whnf Bench2.addSmallLoop addSmallParam
            , C.bench "New3"    $ C.whnf Bench3.addSmallLoop addSmallParam
            , C.bench "New4"    $ C.whnf Bench4.addSmallLoop addSmallParam
            ]

addBigBench :: ([Int], [Int]) -> C.Benchmark
addBigBench addBigParam =
    C.bgroup "Big Integer addition and subtraction"
            [ C.bench "GMP"     $ C.whnf BenchG.addBigLoop addBigParam
            , C.bench "New1"    $ C.whnf Bench1.addBigLoop addBigParam
            , C.bench "New2"    $ C.whnf Bench2.addBigLoop addBigParam
            , C.bench "New3"    $ C.whnf Bench3.addBigLoop addBigParam
            , C.bench "New4"    $ C.whnf Bench4.addBigLoop addBigParam
            ]

timesSmallBench :: Int -> C.Benchmark
timesSmallBench loopCount =
    C.bgroup "Small Integer multiplication"
            [ C.bench "GMP"     $ C.whnf BenchG.timesSmallLoop loopCount
            , C.bench "New1"    $ C.whnf Bench1.timesSmallLoop loopCount
            , C.bench "New2"    $ C.whnf Bench2.timesSmallLoop loopCount
            , C.bench "New3"    $ C.whnf Bench3.timesSmallLoop loopCount
            , C.bench "New4"    $ C.whnf Bench4.timesSmallLoop loopCount
            ]

timesSmallBigBench :: Int -> C.Benchmark
timesSmallBigBench loopCount =
    C.bgroup "Small-Big Integer multiplication"
            [ C.bench "GMP"     $ C.whnf BenchG.timesSmallBigLoop loopCount
            , C.bench "New1"    $ C.whnf Bench1.timesSmallBigLoop loopCount
            , C.bench "New2"    $ C.whnf Bench2.timesSmallBigLoop loopCount
            , C.bench "New3"    $ C.whnf Bench3.timesSmallBigLoop loopCount
            , C.bench "New4"    $ C.whnf Bench4.timesSmallBigLoop loopCount
            ]

timesMediumBench :: Int -> C.Benchmark
timesMediumBench loopCount =
    C.bgroup "Medium Integer multiplication"
            [ C.bench "GMP"     $ C.whnf BenchG.timesMediumLoop loopCount
            , C.bench "New1"    $ C.whnf Bench1.timesMediumLoop loopCount
            , C.bench "New2"    $ C.whnf Bench2.timesMediumLoop loopCount
            , C.bench "New3"    $ C.whnf Bench3.timesMediumLoop loopCount
            , C.bench "New4"    $ C.whnf Bench4.timesMediumLoop loopCount
            ]

timesBigBench :: Int -> C.Benchmark
timesBigBench loopCount =
    C.bgroup "Big Integer multiplication"
            [ C.bench "GMP"     $ C.whnf BenchG.timesBigLoop loopCount
            , C.bench "New1"    $ C.whnf Bench1.timesBigLoop loopCount
            , C.bench "New2"    $ C.whnf Bench2.timesBigLoop loopCount
            , C.bench "New3"    $ C.whnf Bench3.timesBigLoop loopCount
            , C.bench "New4"    $ C.whnf Bench4.timesBigLoop loopCount
            ]


--------------------------------------------------------------------------------
-- Command line handling.

data BenchNames
    = SmallPlus
    | BigPlus
    | Plus
    | SmallTimes
    | SmallBigTimes
    | MediumTimes
    | BigTimes
    | Times
    | Small
    deriving (Eq, Ord, Read, Show)


findBenchmarks :: IO [C.Benchmark]
findBenchmarks =
    (mapArgs . splitR) <$> catch
                            (getEnv "INTEGER_BENCH")
                            (\ (_ :: SomeException) -> pure "")
  where
    splitR "" = []
    splitR str =
        case break (== ',') str of
            (hd, []) -> [ hd ]
            (hd, ',':rest) -> hd : splitR rest
            current -> error $ "Bad value : " ++ show current


mapArgs :: [String] -> [C.Benchmark]
mapArgs [] = concatMap matchBenchmarks [ Plus, Times ]
mapArgs args =
    concatMap matchBenchmarks
            . filterDupes Plus [ SmallPlus, BigPlus ]
            . filterDupes Times [ SmallTimes, SmallBigTimes, MediumTimes, BigTimes ]
            . nub . sort $ map read args
  where
    filterDupes x xs opts =
        if x `elem` opts
            then filter (`elem` xs) opts
            else opts


matchBenchmarks :: BenchNames -> [C.Benchmark]
matchBenchmarks name =
    case name of
        SmallPlus -> plusSmallBenchList
        BigPlus -> plusBigBenchList
        Plus -> plusBenchList
        SmallTimes -> timesSmallBenchList
        SmallBigTimes -> timesSmallBigBenchList
        MediumTimes -> timesMediumBenchList
        BigTimes -> timesBigBenchList
        Times -> timesBenchList
        Small -> smallBenchList
  where
    -- (loop count, increment, decrement) increment and decrement should be
    -- chosen so that loop count * (increment - decrement) < maximum value that
    -- can be held in a 64 bit machine word.
    addSmallParam = (3000, 163, 162)

    addBigParam = unsafePerformIO $ mkBigParam 200

    timesSmallLoopCount = 20000
    timesSmallBigLoopCount = 2000
    timesMediumLoopLoopCount = 1000
    timesBigLoopCount = 10

    plusSmallBenchList = [ addSmallBench addSmallParam ]
    plusBigBenchList = [ addBigBench addBigParam ]

    timesSmallBenchList = [ timesSmallBench timesSmallLoopCount ]
    timesSmallBigBenchList = [ timesSmallBigBench timesSmallBigLoopCount ]
    timesMediumBenchList = [ timesMediumBench timesMediumLoopLoopCount ]
    timesBigBenchList = [ timesBigBench timesBigLoopCount ]

    plusBenchList = plusSmallBenchList ++ plusBigBenchList
    timesBenchList = timesSmallBenchList ++ timesSmallBigBenchList ++ timesMediumBenchList ++ timesBigBenchList

    smallBenchList = plusSmallBenchList ++ timesSmallBenchList

--------------------------------------------------------------------------------
-- | A function to create a a set of test parameters to pass to addBigLoop.
-- The three parameter are; a loop count, and two lists of 31 bit Ints to be
-- passed to the mkInteger function of the Integer API.
mkBigParam :: Int -> IO ([Int], [Int])
mkBigParam len = do
    xs <- R.randomRs (0, 0x7fffffff) <$> R.newStdGen
    let (first, rest) = splitAt len xs
        second = take len rest
    pure (first, second)
