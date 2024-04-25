module Commands.Common where

import Cardano.Api (
  AsType (..),
  File (..),
  FromSomeType (..),
  Key (..),
  NetworkId (..),
  NetworkMagic (..),
  PlutusScriptV3,
  PlutusScriptVersion (..),
  PolicyId,
  Script (..),
  SerialiseAsBech32,
  SerialiseAsRawBytes (..),
  SerialiseAsRawBytesError (unSerialiseAsRawBytesError),
  StakeAddressReference (..),
  ToJSON,
  hashScript,
  readFileTextEnvelope,
  readFileTextEnvelopeAnyOf,
  serialiseToBech32,
  serialiseToRawBytesHexText,
  writeFileTextEnvelope,
 )
import Cardano.Api.Shelley (
  PlutusScript (PlutusScriptSerialised),
  StakeCredential (..),
 )
import CredentialManager.Api (Identity, readIdentityFromPEMFile)
import Data.Aeson.Encode.Pretty (encodePretty)
import Data.Bifunctor (Bifunctor (..))
import Data.ByteString (ByteString)
import Data.ByteString.Base16 (decodeBase16Untyped)
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (Foldable (..), asum)
import Data.String (IsString (..))
import qualified Data.Text.IO as T
import Options.Applicative (
  Mod,
  OptionFields,
  Parser,
  ReadM,
  action,
  eitherReader,
  flag',
  help,
  long,
  metavar,
  option,
  readerError,
  short,
  strOption,
 )
import qualified PlutusLedgerApi.V3 as PlutusV1
import PlutusTx (CompiledCode)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

data StakeCredentialFile = StakeKey FilePath | StakeScript FilePath

networkIdParser :: Parser NetworkId
networkIdParser =
  asum
    [ flag' Mainnet $
        fold
          [ long "mainnet"
          , help "Build a mainnet script address"
          ]
    , -- The network magic is unimportant for addresses.
      flag' (Testnet $ NetworkMagic 1) $
        fold
          [ long "testnet"
          , help "Build a testnet script address"
          ]
    ]

policyIdParser :: Mod OptionFields PolicyId -> Parser PolicyId
policyIdParser = option readPolicyId . (<> metavar "POLICY_ID")

outDirParser :: Parser FilePath
outDirParser =
  strOption $
    fold
      [ long "out-dir"
      , short 'o'
      , metavar "DIRECTORY"
      , help
          "A relative path to the directory where the output assets should be written."
      , action "directory"
      ]

stakeCredentialFileParser :: Parser StakeCredentialFile
stakeCredentialFileParser =
  asum
    [ fmap StakeKey $
        strOption $
          fold
            [ long "stake-verification-key-file"
            , metavar "FILE_PATH"
            , help
                "A relative path to the stake verification key to build the script address with."
            , action "file"
            ]
    , fmap StakeScript $
        strOption $
          fold
            [ long "stake-script-file"
            , metavar "FILE_PATH"
            , help "A relative path to the stake script to build the script address with."
            , action "file"
            ]
    ]

readPolicyId :: ReadM PolicyId
readPolicyId = do
  bytes <- readBase16
  either
    (readerError . unSerialiseAsRawBytesError)
    pure
    $ deserialiseFromRawBytes AsPolicyId bytes

readBase16 :: ReadM ByteString
readBase16 =
  eitherReader $
    first (const "Invalid hexadecimal text") . decodeBase16Untyped . fromString

readIdentityFromPEMFile' :: FilePath -> IO Identity
readIdentityFromPEMFile' file =
  readIdentityFromPEMFile file >>= \case
    Left err -> error $ file <> ": " <> err
    Right a -> pure a

readStakeAddressFile :: StakeCredentialFile -> IO StakeAddressReference
readStakeAddressFile =
  fmap StakeAddressByValue . \case
    StakeKey file -> do
      keyResult <- readFileTextEnvelope (AsVerificationKey AsStakeKey) $ File file
      case keyResult of
        Left err -> do
          error $ "Failed to read stake verification key file: " <> show err
        Right key -> pure $ StakeCredentialByKey $ verificationKeyHash key
    StakeScript file -> do
      scriptHashResult <-
        readFileTextEnvelopeAnyOf
          [ FromSomeType (AsPlutusScript AsPlutusScriptV3) $
              hashScript . PlutusScript PlutusScriptV3
          , FromSomeType (AsPlutusScript AsPlutusScriptV3) $
              hashScript . PlutusScript PlutusScriptV3
          , FromSomeType (AsPlutusScript AsPlutusScriptV3) $
              hashScript . PlutusScript PlutusScriptV3
          ]
          (File file)
      case scriptHashResult of
        Left err -> do
          error $ "Failed to read stake script file: " <> show err
        Right hash -> pure $ StakeCredentialByScript hash

writeScriptToFile
  :: FilePath -> FilePath -> CompiledCode a -> IO (Script PlutusScriptV3)
writeScriptToFile dir file code = do
  createDirectoryIfMissing True dir
  let path = dir </> file
  either (error . show) pure
    =<< writeFileTextEnvelope (File path) Nothing plutusScript
  pure $ PlutusScript PlutusScriptV3 plutusScript
  where
    plutusScript = PlutusScriptSerialised $ PlutusV1.serialiseCompiledCode code

writeHexBytesToFile
  :: (SerialiseAsRawBytes a) => FilePath -> FilePath -> a -> IO ()
writeHexBytesToFile dir file a = do
  createDirectoryIfMissing True dir
  let path = dir </> file
  T.writeFile path $ serialiseToRawBytesHexText a

writeBech32ToFile :: (SerialiseAsBech32 a) => FilePath -> FilePath -> a -> IO ()
writeBech32ToFile dir file a = do
  createDirectoryIfMissing True dir
  let path = dir </> file
  T.writeFile path $ serialiseToBech32 a

writeJSONToFile :: (ToJSON a) => FilePath -> FilePath -> a -> IO ()
writeJSONToFile dir file a = do
  createDirectoryIfMissing True dir
  let path = dir </> file
  LBS.writeFile path $ encodePretty a
