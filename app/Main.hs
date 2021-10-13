{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Main where

import System.Environment
import GHC.Generics
import Control.Monad
import Data.List (sortOn, intercalate, nub)
import Data.Char (isHexDigit, digitToInt, toLower)
import Data.Aeson
import Data.Aeson.TH
import qualified Data.ByteString.Lazy as B

term256ColorsJSON = "term_256_colors.json"

errInvalidInput = "Invalid color hex string passed"
errTooManyInputsGiven = "Only one input is supported"
errNoInputsGiven = "No inputs given"

-- Given an input color property (RGB or hex string), find
-- the closest Term 256 color using the Euclidean distance
-- formula.

square :: Int -> Int
square x = x * x

-- TODO: Replace Euclidean distance with a better measurement
--       because it is not the best to get (visually) closest
--       colors.
euclideanDistance :: [Int] -> [Int] -> Float
euclideanDistance a b = sqrt . fromIntegral $ sum $ map square $ zipWith (-) a b

-- Low-cost approximation of Euclidean Distance
-- Taken from https://www.compuphase.com/cmetric.htm
weightedEuclideanDistance :: [Int] -> [Int] -> Float
weightedEuclideanDistance a b = do
    let r1 = fromIntegral $ head a :: Float
    let r2 = fromIntegral $ head b :: Float
    let r = (r1 + r2) / 2
    let dist = map square $ zipWith (-) a b
    let weightG = 4.0
    let weightR = 2 + r / 256
    let weightB = 2 + ((255 - r) / 256)
    sqrt $ weightR * fromIntegral (head dist) + weightG * fromIntegral (dist !! 1) + weightB * fromIntegral (last dist)


data RGB = RGB
           { r :: Int
           , g :: Int
           , b :: Int
           } deriving (Generic, Show)
instance FromJSON RGB
instance ToJSON RGB

data HSL = HSL
           { h :: Float
           , s :: Float
           , l :: Float
           } deriving (Generic, Show)
instance FromJSON HSL
instance ToJSON HSL

data Term256Color = Term256Color
                 { colorId :: Int
                 , hexString ::String 
                 , rgb :: RGB
                 , hsl :: HSL
                 , name :: String
                 } deriving (Generic, Show)
instance FromJSON Term256Color
instance ToJSON Term256Color

data Color = Color
             { colorHex :: String
             , colorRgb :: [Int] 
             } deriving (Generic, Show)
instance FromJSON Color
instance ToJSON Color

data CmpResult = CmpResult
                 { cmpResultHex :: String
                 , cmpResultRgb :: [Int]
                 , cmpResultDistance :: Float
                 } deriving (Generic, Show)
cmpResultToString :: CmpResult -> String
cmpResultToString result = unwords [cmpResultHex result, show $ cmpResultRgb result, show $ cmpResultDistance result]

normalizeColorHex :: String -> String
normalizeColorHex s
    | head s == '#' = tail s
    | otherwise = s

validateInput :: String -> Either String String
validateInput s
        | length ns /= 6 = Left errInvalidInput
        | not $ isHexString' ns = Left errInvalidInput
        | otherwise = Right ns
    where isHexString' = all isHexDigit
          ns = normalizeColorHex s

hexToDec :: String -> Int
hexToDec "" = 0
hexToDec f = charToHex' (head f) * 16 ^ (length f - 1) + hexToDec (tail f)
    where charToHex' c
            | ch == 'a' = 10
            | ch == 'b' = 11
            | ch == 'c' = 12
            | ch == 'd' = 13
            | ch == 'e' = 14
            | ch == 'f' = 15
            | otherwise = digitToInt c
            where ch = toLower c

parseHexString :: String -> [Int]
parseHexString "" = []
parseHexString s = hexToDec (take 2 s) : parseHexString (drop 2 s)

inputToColor :: String -> Color
inputToColor hex = Color {colorHex = map toLower hex, colorRgb = parseHexString hex}

getClosestColors :: Color -> [Color] -> [CmpResult]
getClosestColors inputColor colors = [CmpResult (colorHex c) (colorRgb c) (getDistance' inputColor c) | c <- colors]
    where getDistance' from to = weightedEuclideanDistance (colorRgb from) (colorRgb to)

validateArgs :: [String] -> Color
validateArgs i 
    | null i = error errNoInputsGiven
    | length i > 1 = error errTooManyInputsGiven
    | otherwise = inputToColor inputHex
    where inputHex = case validateInput $ last i of
            Left err -> error err
            Right s -> s

     
main :: IO ()
main = do
    -- Load the contents of the term 256 JSON.
    json <- (eitherDecode <$> B.readFile term256ColorsJSON) :: IO (Either String [Term256Color])
    let term256Colors = case json of
            Left err -> error err
            Right content -> [ inputToColor $ normalizeColorHex $ hexString tc | tc <- content]

    -- Remove grey, black, and whites from the possible list because they shouldn't
    -- match against a color.
    -- TODO: This should be a passable flag
    let filteredTerm256Colors = filter (\color -> length (nub (colorRgb color)) > 1) term256Colors

    -- Read user input
    i <- getArgs
    let inputColor = validateArgs i

    -- Compare colors
    let results = sortOn cmpResultDistance closestColors
            where closestColors = getClosestColors inputColor filteredTerm256Colors

    -- Output results
    putStrLn "Input: " 
    putStrLn $ colorHex inputColor ++ " " ++  show (colorRgb inputColor)
    putStrLn ""
    putStrLn "Results: "
    mapM_ (putStrLn . cmpResultToString) $ take 15 results

