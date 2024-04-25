module Commands.InitColdNFT (
  InitColdNFTCommand (..),
  initColdNFTCommandParser,
  runInitColdNFTCommand,
) where

import Cardano.Api (
  AsType (..),
  File (..),
  NetworkId,
  PaymentCredential (..),
  PlutusScriptVersion (..),
  Script (..),
  SerialiseAsRawBytes (..),
  StakeAddressReference (..),
  hashScript,
  makeShelleyAddress,
  readFileTextEnvelope,
  unsafeHashableScriptData,
 )
import Cardano.Api.Shelley (
  fromPlutusData,
  scriptDataToJsonDetailedSchema,
 )
import Commands.Common (
  StakeCredentialFile,
  networkIdParser,
  outDirParser,
  readIdentityFromPEMFile',
  readStakeAddressFile,
  stakeCredentialFileParser,
  writeBech32ToFile,
  writeHexBytesToFile,
  writeJSONToFile,
  writeScriptToFile,
 )
import CredentialManager.Api (
  ColdLockDatum (..),
 )
import qualified CredentialManager.Scripts as Scripts
import Data.Foldable (Foldable (..))
import Options.Applicative (
  Alternative (some),
  InfoMod,
  Parser,
  ParserInfo,
  action,
  help,
  info,
  long,
  metavar,
  optional,
  progDesc,
  strOption,
 )
import PlutusLedgerApi.V3 (
  ColdCommitteeCredential (..),
  Credential (..),
  ScriptHash (..),
  toBuiltin,
  toData,
 )

data InitColdNFTCommand = InitColdNFTCommand
  { networkId :: NetworkId
  , coldCredentialScriptFile :: FilePath
  , caCertFile :: FilePath
  , membershipCertFiles :: [FilePath]
  , delegationCertFiles :: [FilePath]
  , stakeCredentialFile :: Maybe StakeCredentialFile
  , outDir :: FilePath
  }

initColdNFTCommandParser :: ParserInfo InitColdNFTCommand
initColdNFTCommandParser = info parser description
  where
    description :: InfoMod InitColdNFTCommand
    description =
      progDesc "Initialize the cold NFT lock script by sending an NFT to it."

    parser :: Parser InitColdNFTCommand
    parser =
      InitColdNFTCommand
        <$> networkIdParser
        <*> coldCredentialScriptFileParser
        <*> caCertFileParser
        <*> some membershipFileParser
        <*> some delegationFileParser
        <*> optional stakeCredentialFileParser
        <*> outDirParser

coldCredentialScriptFileParser :: Parser FilePath
coldCredentialScriptFileParser =
  strOption $
    fold
      [ long "cold-credential-script-file"
      , metavar "FILE_PATH"
      , help "A relative path to the compiled cold credential script file."
      , action "file"
      ]

caCertFileParser :: Parser FilePath
caCertFileParser =
  strOption $
    fold
      [ long "ca-cert"
      , metavar "FILE_PATH"
      , help "A relative path to the root CA certificate PEM file."
      , action "file"
      ]

membershipFileParser :: Parser FilePath
membershipFileParser =
  strOption $
    fold
      [ long "membership-cert"
      , metavar "FILE_PATH"
      , help "A relative path to the certificate PEM file of a membership user."
      , action "file"
      ]

delegationFileParser :: Parser FilePath
delegationFileParser =
  strOption $
    fold
      [ long "delegation-cert"
      , metavar "FILE_PATH"
      , help "A relative path to the certificate PEM file of a delegation user."
      , action "file"
      ]

runInitColdNFTCommand :: InitColdNFTCommand -> IO ()
runInitColdNFTCommand InitColdNFTCommand{..} = do
  coldCredentialScriptResult <-
    readFileTextEnvelope
      (AsPlutusScript AsPlutusScriptV3)
      (File coldCredentialScriptFile)

  stakeAddress <-
    maybe
      (pure NoStakeAddress)
      readStakeAddressFile
      stakeCredentialFile

  coldCredentialScript <- case coldCredentialScriptResult of
    Left err -> do
      error $ "Failed to read cold credential script file: " <> show err
    Right script -> pure $ PlutusScript PlutusScriptV3 script

  certificateAuthority <- readIdentityFromPEMFile' caCertFile
  membershipUsers <- traverse readIdentityFromPEMFile' membershipCertFiles
  delegationUsers <- traverse readIdentityFromPEMFile' delegationCertFiles

  let coldCredentialScriptHash =
        ScriptHash $
          toBuiltin $
            serialiseToRawBytes $
              hashScript coldCredentialScript
  let coldCredential =
        ColdCommitteeCredential $ ScriptCredential coldCredentialScriptHash
  let compiledScript = Scripts.coldNFT coldCredential
  script <- writeScriptToFile outDir "script.plutus" compiledScript

  let scriptHash = hashScript script
  writeHexBytesToFile outDir "script.hash" scriptHash

  let paymentCredential = PaymentCredentialByScript scriptHash
  writeBech32ToFile outDir "script.addr" $
    makeShelleyAddress networkId paymentCredential stakeAddress

  let datum = ColdLockDatum{..}
  let datumEncoded = unsafeHashableScriptData $ fromPlutusData $ toData datum
  writeJSONToFile outDir "datum.json" $
    scriptDataToJsonDetailedSchema datumEncoded
