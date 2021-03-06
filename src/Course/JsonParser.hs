{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module Course.JsonParser where

import Course.Core
import Course.Parser
import Course.MoreParser
import Course.JsonValue
import Course.Functor
import Course.Apply
import Course.Applicative
import Course.Bind
import Course.List
import Course.Optional

-- $setup
-- >>> :set -XOverloadedStrings

-- | Parse a JSON string. Handle double-quotes, control characters, hexadecimal characters.
--
-- /Tip:/ Use `oneof`, `hex`, `is`, `satisfyAll`, `betweenCharTok`, `list`.
--
-- >>> parse jsonString "\"abc\""
-- Result >< "abc"
--
-- >>> parse jsonString "\"abc\"def"
-- Result >def< "abc"
--
-- >>> parse jsonString "\"\\babc\"def"
-- Result >def< "babc"
--
-- >>> parse jsonString "\"\\u00abc\"def"
-- Result >def< "\171c"
--
-- >>> parse jsonString "\"\\u00ffabc\"def"
-- Result >def< "\255abc"
--
-- >>> parse jsonString "\"\\u00faabc\"def"
-- Result >def< "\250abc"
--
-- >>> isErrorResult (parse jsonString "abc")
-- True
--
-- >>> isErrorResult (parse jsonString "\"\\abc\"def")
-- True
jsonString :: Parser Chars
jsonString = betweenCharTok '"' '"' content
    where content = list chars
          chars = ((is '\\') >>> (hex ||| oneof "b\"rf")) ||| noneof "\\\""

-- | Parse a JSON rational.
--
-- /Tip:/ Use @readFloats@.
--
-- >>> parse jsonNumber "234"
-- Result >< 234 % 1
--
-- >>> parse jsonNumber "-234"
-- Result >< (-234) % 1
--
-- >>> parse jsonNumber "123.45"
-- Result >< 2469 % 20
--
-- >>> parse jsonNumber "-123"
-- Result >< (-123) % 1
--
-- >>> parse jsonNumber "-123.45"
-- Result >< (-2469) % 20
--
-- >>> isErrorResult (parse jsonNumber "-")
-- True
--
-- >>> isErrorResult (parse jsonNumber "abc")
-- True
jsonNumber :: Parser Rational
jsonNumber = (is '-' >>= mag) ||| mag ' '
    where mag si = digits1 >>= \int ->
                   (is '.' >>= \d -> digits1 >>=
                    \float -> getFloat (int++(d:.float)) si)
                   ||| getFloat int si
          getFloat ss si = case readFloat (si:.ss) of
                             Full x -> return x
                             _ -> failed

-- | Parse a JSON true literal.
--
-- /Tip:/ Use `stringTok`.
--
-- >>> parse jsonTrue "true"
-- Result >< "true"
--
-- >>> isErrorResult (parse jsonTrue "TRUE")
-- True
jsonTrue :: Parser Chars
jsonTrue = stringTok "true"

-- | Parse a JSON false literal.
--
-- /Tip:/ Use `stringTok`.
--
-- >>> parse jsonFalse "false"
-- Result >< "false"
--
-- >>> isErrorResult (parse jsonFalse "FALSE")
-- True
jsonFalse :: Parser Chars
jsonFalse = stringTok "false"

-- | Parse a JSON null literal.
--
-- /Tip:/ Use `stringTok`.
--
-- >>> parse jsonNull "null"
-- Result >< "null"
--
-- >>> isErrorResult (parse jsonNull "NULL")
-- True
jsonNull :: Parser Chars
jsonNull = stringTok "null"

-- | Parse a JSON array.
--
-- /Tip:/ Use `betweenSepbyComma` and `jsonValue`.
--
-- >>> parse jsonArray "[]"
-- Result >< []
--
-- >>> parse jsonArray "[true]"
-- Result >< [JsonTrue]
--
-- >>> parse jsonArray "[true, \"abc\"]"
-- Result >< [JsonTrue,JsonString "abc"]
--
-- >>> parse jsonArray "[true, \"abc\", []]"
-- Result >< [JsonTrue,JsonString "abc",JsonArray []]
--
-- >>> parse jsonArray "[true, \"abc\", [false]]"
-- Result >< [JsonTrue,JsonString "abc",JsonArray [JsonFalse]]
jsonArray :: Parser (List JsonValue)
jsonArray = betweenSepbyComma '[' ']' jsonValue

-- | Parse a JSON object.
--
-- /Tip:/ Use `jsonString`, `charTok`, `betweenSepbyComma` and `jsonValue`.
--
-- >>> parse jsonObject "{}"
-- Result >< []
--
-- >>> parse jsonObject "{ \"key1\" : true }"
-- Result >< [("key1",JsonTrue)]
--
-- >>> parse jsonObject "{ \"key1\" : true , \"key2\" : false }"
-- Result >< [("key1",JsonTrue),("key2",JsonFalse)]
--
-- >>> parse jsonObject "{ \"key1\" : true , \"key2\" : false } xyz"
-- Result >xyz< [("key1",JsonTrue),("key2",JsonFalse)]
jsonObject :: Parser Assoc
jsonObject = spaces >>> betweenSepbyComma '{' '}' inner >>= \v ->
             spaces >>> (return v)
    where inner = spaces >>> jsonString >>= \key ->
                  charTok ':' >>> jsonValue >>= \val ->
                      spaces >>> (return $ (key, val))


-- | Parse a JSON value.
--
-- /Tip:/ Use `spaces`, `jsonNull`, `jsonTrue`, `jsonFalse`, `jsonArray`, `jsonString`, `jsonObject` and `jsonNumber`.
--
-- >>> parse jsonValue "true"
-- Result >< JsonTrue
--
-- >>> parse jsonObject "{ \"key1\" : true , \"key2\" : [7, false] }"
-- Result >< [("key1",JsonTrue),("key2",JsonArray [JsonRational False (7 % 1),JsonFalse])]
--
-- >>> parse jsonObject "{ \"key1\" : true , \"key2\" : [7, false] , \"key3\" : { \"key4\" : null } }"
-- Result >< [("key1",JsonTrue),("key2",JsonArray [JsonRational False (7 % 1),JsonFalse]),("key3",JsonObject [("key4",JsonNull)])]
jsonValue :: Parser JsonValue
jsonValue = spaces >>>
            ((jsonNull >>= \_ -> return $ JsonNull)
             ||| (jsonTrue >>= \_ -> return $ JsonTrue)
             ||| (jsonFalse >>= \_ -> return $ JsonFalse)
             ||| (jsonArray >>= \x -> return $ JsonArray x)
             ||| (jsonString >>= \x -> return $ JsonString x)
             ||| (jsonObject >>= \x -> return $ JsonObject x)
             ||| (jsonNumber >>= \x -> return $ JsonRational False x))

-- | Read a file into a JSON value.
--
-- /Tip:/ Use @System.IO#readFile@ and `jsonValue`.
readJsonValue :: Filename -> IO (ParseResult JsonValue)
readJsonValue = ((parse jsonValue) <$>) . readFile
